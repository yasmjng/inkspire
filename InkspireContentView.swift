// all my import stuff
import SwiftUI
import UIKit
import Combine
import AVFoundation
import CryptoKit
import SQLite3
import Charts
import PDFKit
import UniformTypeIdentifiers


//extensions listed at top of file (swift convention)

// extension to UIBezierPath to calculate path length and point at percentage
extension UIBezierPath {
    var length: CGFloat {
        var pathLength: CGFloat = 0
        var currentPoint = CGPoint.zero

        // helper function to process each path element
        func processPathElement(_ element: UnsafePointer<CGPathElement>) {
            let points = element.pointee.points

            switch element.pointee.type {
            case .moveToPoint:
                currentPoint = points[0]
            case .addLineToPoint:
                let nextPoint = points[0]
                pathLength += hypot(nextPoint.x - currentPoint.x, nextPoint.y - currentPoint.y)
                currentPoint = nextPoint
            case .addQuadCurveToPoint:
                let nextPoint = points[1]
                // use more accurate curve length calculation for quad curves
                let controlPoint = points[0]
                pathLength += approximateCurveLength(start: currentPoint, control: controlPoint, end: nextPoint, steps: 10)
                currentPoint = nextPoint
            case .addCurveToPoint:
                let nextPoint = points[2]
                // use more accurate curve length calculation for cubic curves
                let control1 = points[0]
                let control2 = points[1]
                pathLength += approximateCurveLength(start: currentPoint, control1: control1, control2: control2, end: nextPoint, steps: 10)
                currentPoint = nextPoint
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }

        cgPath.applyWithBlock(processPathElement)
        return pathLength
    }


    // make curve length more accurate for any Bézier curve
    private func approximateCurveLength(points: [CGPoint], steps: Int) -> CGFloat {
        var length: CGFloat = 0
        var prevPoint = points.first!
        let count = points.count

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let t1 = 1 - t
            let point: CGPoint

            switch count {
            case 3:
                // quadratic Bézier
                point = CGPoint(
                    x: pow(t1, 2) * points[0].x + 2 * t1 * t * points[1].x + pow(t, 2) * points[2].x,
                    y: pow(t1, 2) * points[0].y + 2 * t1 * t * points[1].y + pow(t, 2) * points[2].y
                )
            case 4:
                // cubic Bézier
                point = CGPoint(
                    x: pow(t1, 3) * points[0].x + 3 * pow(t1, 2) * t * points[1].x + 3 * t1 * pow(t, 2) * points[2].x + pow(t, 3) * points[3].x,
                    y: pow(t1, 3) * points[0].y + 3 * pow(t1, 2) * t * points[1].y + 3 * t1 * pow(t, 2) * points[2].y + pow(t, 3) * points[3].y
                )
            default:
                fatalError("Unsupported number of points for curve length calculation")
            }

            length += hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            prevPoint = point
        }

        return length
    }

    // makes quad curve length more acc
    private func approximateCurveLength(start: CGPoint, control: CGPoint, end: CGPoint, steps: Int) -> CGFloat {
        return approximateCurveLength(points: [start, control, end], steps: steps)
    }

    // makes cubic curve length more acc
    private func approximateCurveLength(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, steps: Int) -> CGFloat {
        return approximateCurveLength(points: [start, control1, control2, end], steps: steps)
    }

    func point(at percentage: CGFloat) -> CGPoint {
        let targetLength = length * percentage
        var currentLength: CGFloat = 0
        var lastPoint = CGPoint.zero
        var resultPoint = CGPoint.zero
        var foundPoint = false

        // processes each path element
        func processPathElement(_ element: UnsafePointer<CGPathElement>) {
            if foundPoint { return }
            let points = element.pointee.points

            switch element.pointee.type {
            case .moveToPoint:
                lastPoint = points[0]
            case .addLineToPoint:
                let nextPoint = points[0]
                let segmentLength = hypot(nextPoint.x - lastPoint.x, nextPoint.y - lastPoint.y)

                if currentLength + segmentLength >= targetLength {
                    let remaining = targetLength - currentLength
                    let pct = remaining / segmentLength
                    resultPoint = CGPoint(
                        x: lastPoint.x + (nextPoint.x - lastPoint.x) * pct,
                        y: lastPoint.y + (nextPoint.y - lastPoint.y) * pct
                    )
                    foundPoint = true
                }

                currentLength += segmentLength
                lastPoint = nextPoint
            case .addQuadCurveToPoint:
                let controlPoint = points[0]
                let endPoint = points[1]
                // finds point
                let curveLength = approximateCurveLength(start: lastPoint, control: controlPoint, end: endPoint, steps: 10)

                if currentLength + curveLength >= targetLength {
                    let steps = 50 // More steps for accuracy
                    let remaining = targetLength - currentLength
                    let pct = remaining / curveLength

                    // finds more accurate point on curve
                    let t = findParameterForLength(start: lastPoint, control: controlPoint, end: endPoint, targetLength: pct * curveLength, steps: steps)
                    let t1 = 1 - t
                    resultPoint = CGPoint(
                        x: pow(t1, 2) * lastPoint.x + 2 * t1 * t * controlPoint.x + pow(t, 2) * endPoint.x,
                        y: pow(t1, 2) * lastPoint.y + 2 * t1 * t * controlPoint.y + pow(t, 2) * endPoint.y
                    )
                    foundPoint = true
                }

                currentLength += curveLength
                lastPoint = endPoint
            case .addCurveToPoint:
                let control1 = points[0]
                let control2 = points[1]
                let endPoint = points[2]
                // sample cubic curve to find point
                let curveLength = approximateCurveLength(start: lastPoint, control1: control1, control2: control2, end: endPoint, steps: 10)

                if currentLength + curveLength >= targetLength {
                    let steps = 50 // higher steps for accuracy
                    let remaining = targetLength - currentLength
                    let pct = remaining / curveLength

                    let t = findParameterForLength(start: lastPoint, control1: control1, control2: control2, end: endPoint, targetLength: pct * curveLength, steps: steps)
                    let t1 = 1 - t
                    resultPoint = CGPoint(
                        x: pow(t1, 3) * lastPoint.x + 3 * pow(t1, 2) * t * control1.x + 3 * t1 * pow(t, 2) * control2.x + pow(t, 3) * endPoint.x,
                        y: pow(t1, 3) * lastPoint.y + 3 * pow(t1, 2) * t * control1.y + 3 * t1 * pow(t, 2) * control2.y + pow(t, 3) * endPoint.y
                    )
                    foundPoint = true
                }

                currentLength += curveLength
                lastPoint = endPoint
            default:
                break
            }
        }

        cgPath.applyWithBlock(processPathElement)
        return resultPoint
    }

    // finds parameter value t for quad curve
    private func findParameterForLength(start: CGPoint, control: CGPoint, end: CGPoint, targetLength: CGFloat, steps: Int) -> CGFloat {
        var accumulatedLength: CGFloat = 0
        var prevPoint = start

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let t1 = 1 - t
            let point = CGPoint(
                x: pow(t1, 2) * start.x + 2 * t1 * t * control.x + pow(t, 2) * end.x,
                y: pow(t1, 2) * start.y + 2 * t1 * t * control.y + pow(t, 2) * end.y
            )
            let segmentLength = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            accumulatedLength += segmentLength

            if accumulatedLength >= targetLength {
                return t
            }

            prevPoint = point
        }

        return 1.0
    }

    // finds parameter value t for cubic curve
    private func findParameterForLength(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, targetLength: CGFloat, steps: Int) -> CGFloat {
        var accumulatedLength: CGFloat = 0
        var prevPoint = start

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let t1 = 1 - t
            let point = CGPoint(
                x: pow(t1, 3) * start.x + 3 * pow(t1, 2) * t * control1.x + 3 * t1 * pow(t, 2) * control2.x + pow(t, 3) * end.x,
                y: pow(t1, 3) * start.y + 3 * pow(t1, 2) * t * control1.y + 3 * t1 * pow(t, 2) * control2.y + pow(t, 3) * end.y
            )
            let segmentLength = hypot(point.x - prevPoint.x, point.y - prevPoint.y)
            accumulatedLength += segmentLength

            if accumulatedLength >= targetLength {
                return t
            }

            prevPoint = point
        }

        return 1.0
    }
}

// tracingappview extension bc it was too long lol
extension TracingAppView {
    var enhancedAnimationZStack: some View {
        ZStack {
            // dotted paper effect 4 aesthetic
            VStack(spacing: 15) {
                ForEach(0..<20, id: \.self) { _ in
                    HStack(spacing: 15) {
                        ForEach(0..<20, id: \.self) { _ in
                            Circle()
                                .fill(AppTheme.primaryColor.opacity(0.1))
                                .frame(width: 3, height: 3)
                        }
                    }
                }
            }
            .padding()

            // faded big letter in the background
            Text(letters[currentLetterIndex])
                .font(.system(size: 200, weight: .bold, design: .rounded))
                .foregroundColor(Color.gray.opacity(0.1))

            // score progress bar (one box per letter)
            VStack {
                MultiLetterProgressBar(scores: testScores)
                    .padding(.top, 12)

                Spacer()

                // live tracing stroke progress for updates
                if isTrySampleMode {
                    ProgressView(value: strokeProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: themedProgressColor(for: strokeProgress)))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .id(Int(strokeProgress * 100))
                        .animation(.easeInOut(duration: 0.3), value: strokeProgress)
                }
            }

            // letter animation
            if isTrySampleMode {
                if EnhancedLetterPathFactory.letterNeedsPenLifting(letters[currentLetterIndex]) {
                    EnhancedTracingAnimatedPathView(
                        letter: letters[currentLetterIndex],
                        progress: strokeProgress
                    )
                } else {
                    TracingAnimatedPathView(letter: letters[currentLetterIndex], progress: strokeProgress)
                        .stroke(AppTheme.secondaryColor, lineWidth: 6)
                        .shadow(color: AppTheme.secondaryColor.opacity(0.5), radius: 3)
                }
            } else if showPath {
                TracingPathView(letter: letters[currentLetterIndex])
                    .stroke(AppTheme.primaryColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 8]))
                    .opacity(0.7)
            }

            // drawn segments
            ForEach(0..<userDrawnSegments.count, id: \.self) { index in
                userDrawnSegments[index]
                    .stroke(AppTheme.successColor, lineWidth: 6)
                    .shadow(color: AppTheme.successColor.opacity(0.5), radius: 2)
            }

            userDrawnPath
                .stroke(AppTheme.successColor, lineWidth: 6)
                .shadow(Color: AppTheme.successColor.opacity(0.5), radius: 2)

            // guides
            if showNumberedGuide && !isTrySampleMode {
                EnhancedNumberedPathGuideView(letter: letters[currentLetterIndex])
            }

            if showArrows && !isTrySampleMode {
                DirectionalArrowsView(letter: letters[currentLetterIndex], style: .enhanced)
                    .opacity(guideOpacity)
            }
        }
    }

    // theme-based live progress colour
    func themedProgressColor(for progress: Double) -> Color {
        switch progress {
        case ..<0.3: return AppTheme.funPink
        case 0.3..<0.7: return AppTheme.accentColor
        default: return AppTheme.funGreen
        }
    }
}

extension Binding where Value == Bool {
    var not: Binding<Value> {
        Binding<Value>(
            get: { !self.wrappedValue },
            set: { self.wrappedValue = !$0 }
        )
    }
}

// view so that it includes application of the enhanced visual preference (!!!including dark mode)
extension View {
    
    func enhancedVisualPreference(_ preferences: UserPreferences?) -> some View {
        self.modifier(VisualPreferenceModifier(preferences: preferences))
    }

    func applyVisualPreference(_ preferences: UserPreferences?) -> some View {
        self.modifier(VisualPreferenceModifier(preferences: preferences))
    }
    
// making view more kiddy
    //  'cheerful' shadows to elements
    func cheerfulShadow() -> some View {
        self.shadow(color: AppTheme.primaryColor.opacity(0.3), radius: 5, x: 2, y: 2)
    }
    
    // rainbow gradient background (shifting?)
    func rainbowBackground() -> some View {
        self.background(
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.funPink,
                    AppTheme.funPurple,
                    AppTheme.funBlue,
                    AppTheme.funGreen
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted))
        var int: UInt64 = 0
        scanner.scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
    static func fromHex(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17,
                                 (int >> 4 & 0xF) * 17,
                                 (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16,
                                 int >> 8 & 0xFF,
                                 int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24,
                           int >> 16 & 0xFF,
                           int >> 8 & 0xFF,
                           int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 0, 0) // fallback red for broken hex
        }

        return Color(.sRGB,
                     red: Double(r) / 255,
                     green: Double(g) / 255,
                     blue: Double(b) / 255,
                     opacity: Double(a) / 255)
    }
}

extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}

extension HomeDashboardView {
    private var exitButton: some View {
        Button(action: {
            //  simulate exit via logout ((or app suspension))...
            UIControl().sendAction(#selector(NSXPCConnection.suspend), to: UIApplication.shared, for: nil)
        }) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                Text("Exit App")
            }
            .padding()
            .foregroundColor(.white)
            .background(Color.red.opacity(0.8))
            .cornerRadius(12)
        }
        .padding(.bottom, 20)
    }
}

extension String: Identifiable {
    public var id: String { self }
}

extension Notification.Name {
    static let tracingCompleted = Notification.Name("tracingCompleted")
}

// so user can change visual pref (high/low(reg) contrast
struct VisualPreferenceModifier: ViewModifier {
    let preferences: UserPreferences?

    func body(content: Content) -> some View {
        if let preferences = preferences {
            switch preferences.visualPreference {
            case .darkMode:
                content
                    .environment(\.colorScheme, .dark)
                    .background(AppTheme.adaptiveBackgroundColor(preferences: preferences))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))

            case .lightMode:
                content
                    .environment(\.ColorScheme, .light)
                    .background(AppTheme.adaptiveBackgroundColor(preferences: preferences))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))

            case .reducedMotion:
                content
                    .transaction { $0.animation = nil }
            }
        } else {
            // Default fallback if preferences are missing
            content
                .environment(\.ColorScheme, .light)
                .background(AppTheme.backgroundColor)
                .foregroundColor(.primary)
        }
    }
}

// audio feedback
// audios imported from *** website (can't remember, add later)
class SoundManager {
    static let shared = SoundManager()
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var isMuted = false
    weak var authManager: AuthManager?
    
    // sound effects with their file extensions (matches desktop)
    private struct SoundFile {
        let name: String
        let ext: String
    }
    // funny sound effects
    private let successSound = SoundFile(name: "404358__kagateni__success", ext: "wav")
    private let errorSound = SoundFile(name: "351500__thehorriblejoke__error-sound", ext: "mp3")
    private let clickSound = SoundFile(name: "213004__abstraktgeneriert__mouse-click", ext: "wav")
    private let drawSound = SoundFile(name: "761651__jellydaisies__pencil-scribble-14", ext: "wav")
    private let completeSound = SoundFile(name: "270545__littlerobotsoundfactory__jingle_win_01", ext: "wav")
    private let celebrationSound = SoundFile(name: "352884__robinhood76__06829-tabla-up-completed", ext: "wav")
    
    private init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func preloadSounds() {
        let sounds = [successSound, errorSound, clickSound, drawSound, completeSound, celebrationSound]
        for sound in sounds {
            if let path = Bundle.main.path(forResource: sound.name, ofType: sound.ext) {
                let url = URL(fileURLWithPath: path)
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.prepareToPlay()
                    audioPlayers[sound.name] = player
                } catch {
                    print("Could not load sound: \(sound.name)")
                }
            }
        }
    }
    
    private func playSound(_ sound: SoundFile) {
        if let path = Bundle.main.path(forResource: sound.name, ofType: sound.ext) {
            let url = URL(fileURLWithPath: path)
            if let player = audioPlayers[sound.name] {
                if !player.isPlaying {
                    player.currentTime = 0
                    player.play()
                }
            } else {
                // failsafe if not preloaded
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.play()
                } catch {
                    print("Could not play sound: \(sound.name)")
                }
            }
        }
    }
    
    // sound effect methods
    func setMuted(_ muted: Bool) {
        isMuted = muted
    }
    
    // sound methods but using the mute setting
    // if user requests no sound, methods not used
    func playSuccess() {
        if !isMuted {
            playSound(successSound)
        }
    }
    
    func playError() {
        if !isMuted {
            playSound(errorSound)
        }
    }
    
    func playClick() {
        if !isMuted {
            playSound(clickSound)
        }
    }
    
    func playDrawSound() {
        if !isMuted {
            playSound(drawSound)
        }
    }
    
    func playComplete() {
        if !isMuted {
            playSound(completeSound)
        }
    }
    
    func playCelebration() {
        if !isMuted {
            playSound(celebrationSound)
        }
    }
}

class StudentPerformance: Identifiable, Codable {
    var id: String
    var studentName: String
    var letterPerformances: [LetterPerformance]
    var totalRewards: Int
    var consecutiveDayStreak: Int
    var lastPracticeDate: Date
    var lastLetterPracticed: String?
    
    init(id: String, studentName: String, letterPerformances: [LetterPerformance], totalRewards: Int = 0, consecutiveDayStreak: Int = 0, lastPracticeDate: Date = Date().addingTimeInterval(-86400)) {
        self.id = id
        self.studentName = studentName
        self.letterPerformances = letterPerformances
        self.totalRewards = totalRewards
        self.consecutiveDayStreak = consecutiveDayStreak
        self.lastPracticeDate = lastPracticeDate
    }
    
    // Overall average score for all letters
    var overallAverage: Double {
        letterPerformances.isEmpty ? 0 :
            letterPerformances.reduce(0) { $0 + $1.averageScore } / Double(letterPerformances.count)
    }
    
    // Get letters that need improvement (below 70% average)
    var lettersNeedingImprovement: [LetterPerformance] {
        letterPerformances
            .filter { $0.averageScore < 70 }
            .sorted { $0.averageScore < $1.averageScore }
    }
    
    // Get mastered letters
    var masteredLetters: [LetterPerformance] {
        letterPerformances
            .filter { $0.isMastered }
            .sorted { $0.letter < $1.letter }
    }
}

class PerformanceManager {
    static let shared = PerformanceManager()
    private init() {}

    func awardRewards(for letter: String, with score: Double, to studentId: String) {
        var rewardsToAdd: [String] = []

        let allLetters = SQLiteManager.shared.getLetterPerformances(for: studentId)
        let studentInfo = SQLiteManager.shared.getStudentPerformance(for: studentId)

        guard var letterData = allLetters[letter] else {
            print("Letter data not found for \(letter)")
            return
        }

        let previousAverage = letterData.scores.isEmpty ? 0 : (letterData.scores.reduce(0, +) / Double(letterData.scores.count))
        let previousAttempts = letterData.attempts
        
// emoji 'scores'
        if previousAttempts == 0 { rewardsToAdd.append("🎯") }
        if score >= 90 { rewardsToAdd.append("⭐️") }
        if score >= 95 { rewardsToAdd.append("🌟") }
        if score >= 98 { rewardsToAdd.append("🏆") }
        if previousAttempts > 0 && score > previousAverage + 15 { rewardsToAdd.append("📈") }
        if score >= 85 && previousAttempts >= 2 {
            if !letterData.rewards.contains("🎨") {
                rewardsToAdd.append("🎨")
            }
        }

        if let streak = studentInfo?.streak, streak > 0, streak % 3 == 0 {
            rewardsToAdd.append("🔥")
        }

        if Bool.random() && score >= 80 {
            let bonusRewards = ["✏️", "🖌️", "🎊", "🎭", "🎲"]
            if let bonus = bonusRewards.randomElement() {
                rewardsToAdd.append(bonus)
            }
        }

        SQLiteManager.shared.saveLetterPerformance(
            userId: studentId,
            letter: letter,
            newScore: score,
            newRewards: rewardsToAdd
        )

        if let info = studentInfo {
            SQLiteManager.shared.saveStudentPerformance(
                id: studentId,
                name: info.name,
                totalRewards: info.totalRewards + rewardsToAdd.count,
                streak: info.streak,
                lastPracticeDate: Date()
            )
        }

        if rewardsToAdd.isEmpty {
            if score >= 80 {
                SoundManager.shared.playComplete()
            } else {
                SoundManager.shared.playSuccess()
            }
        } else {
            SoundManager.shared.playCelebration()
        }
    }

    func updateStreak(for studentId: String) {
        guard var performance = SQLiteManager.shared.getStudentPerformance(for: studentId) else { return }

        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!

        let lastPractice = calendar.startOfDay(for: performance.lastPracticeDate)
        let yesterdayStart = calendar.startOfDay(for: yesterday)

        if lastPractice == yesterdayStart {
            performance.streak += 1
        } else if lastPractice < yesterdayStart {
            performance.streak = 0
        }

        SQLiteManager.shared.saveStudentPerformance(
            id: studentId,
            name: performance.name,
            totalRewards: performance.totalRewards,
            streak: performance.streak,
            lastPracticeDate: performance.lastPracticeDate
        )
    }
}

struct CharacterSelectionButton: View {
    let character: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var bounce = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(isSelected ? AppTheme.primaryColor.opacity(0.2) : Color.white)
                    .frame(width: 80, height: 80)
                    .shadow(color: isSelected ? AppTheme.primaryColor.opacity(0.5) : Color.black.opacity(0.1),
                            radius: isSelected ? 5 : 2)
                
                Text(character)
                    .font(.system(size: 40))
                    .scaleEffect(bounce && isSelected ? 1.1 : 1.0)
                
                if isSelected {
                    Circle()
                        .stroke(AppTheme.primaryColor, lineWidth: 3)
                        .frame(width: 80, height: 80)
                }
            }
            .onAppear {
                if isSelected {
                    withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        bounce = true
                    }
                }
            }
            .onChange(of: isSelected) { _, newValue in
                if newValue {
                    withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        bounce = true
                    }
                } else {
                    bounce = false
                }
            }
        }
    }
}

struct AccessibilitySettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode

    @State private var preferences: UserPreferences
    @State private var showSavedMessage = false
    @State private var isMuted = false
    @State private var isDarkMode = false

    // initalise with current preferences :)
    init(currentPreferences: UserPreferences) {
        _preferences = State(initialValue: currentPreferences)
        _isMuted = State(initialValue: currentPreferences.soundPreference == .none)
        _isDarkMode = State(initialValue: currentPreferences.visualPreference == .darkMode)
    }

    var body: some View {
        NavigationView {
            ZStack {
                let backgroundColor = isDarkMode ? AppTheme.backgroundColorDark : AppTheme.backgroundColor

                backgroundColor
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 25) {
                        let titleFont = AppTheme.roundedFont(size: 28, weight: .bold)
                        let titleColor = AppTheme.adaptivePrimaryColor(preferences: preferences)

                        Text("Accessibility Settings")
                            .font(titleFont)
                            .foregroundColor(titleColor)
                            .padding(.top)

                        visualSettingsSection
                        soundSettingsSection
                        howToUseSection
                        saveButton
                    }
                    .padding(.bottom, 30)
                }

                if showSavedMessage {
                    VStack {
                        Text("Settings Saved! ✓")
                            .font(AppTheme.roundedFont(size: 20, weight: .bold))
                            .foregroundColor(isDarkMode ? .white : .black)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(isDarkMode ? Color(UIColor.darkGray) : Color.white)
                                    .shadow(radius: 5)
                            )
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
            .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences)))
            .navigationBarTitle("", displayMode: .inline)
            .onChange(of: preferences.visualPreference) { _, newValue in
                isDarkMode = (newValue == .darkMode)
            }
        }
    }

    private var visualSettingsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            headerIcon("eye.fill", title: "Visual Settings")

            VStack(alignment: .leading, spacing: 10) {
                Text("Display Mode")
                    .font(AppTheme.roundedFont(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))

                HStack {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(isDarkMode ? .purple : .orange)
                        .font(.system(size: 24))

                    Toggle("Dark Mode", isOn: $isDarkMode)
                        .toggleStyle(SwitchToggleStyle(tint: AppTheme.adaptivePrimaryColor(preferences: preferences)))
                        .onChange(of: isDarkMode) { _, newValue in
                            withAnimation {
                                preferences.visualPreference = newValue ? .darkMode : .lightMode
                            }
                        }
                }
                .padding(.bottom, 5)

                Toggle("Reduce Motion", isOn: Binding(
                    get: { preferences.visualPreference == .reducedMotion },
                    set: { if $0 { preferences.visualPreference = .reducedMotion } }
                ))
                .toggleStyle(SwitchToggleStyle(tint: AppTheme.adaptivePrimaryColor(preferences: preferences)))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                    .shadow(color: isDarkMode ? Color.black.opacity(0.25) : Color.black.opacity(0.1), radius: 3)
            )
        }
        .padding(.horizontal)
    }

    private var soundSettingsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            headerIcon("speaker.wave.2.fill", title: "Sound Settings")

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Sound On", isOn: $isMuted.not)
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.adaptivePrimaryColor(preferences: preferences)))
                    .onChange(of: isMuted) { _, newValue in
                        preferences.soundPreference = newValue ? .none : .all
                        SoundManager.shared.setMuted(newValue)
                    }
                    .padding(.top, 5)
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))

                Toggle("Enable Animations", isOn: $preferences.animationsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.adaptivePrimaryColor(preferences: preferences)))
                    .padding(.top, 5)
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))

                Button(action: playSoundTest) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Test Sound")
                            .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.adaptivePrimaryColor(preferences: preferences), lineWidth: 1)
                    )
                }
                .padding(.top, 5)
                .disabled(isMuted)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                    .shadow(color: isDarkMode ? Color.black.opacity(0.25) : Color.black.opacity(0.1), radius: 3)
            )
        }
        .padding(.horizontal)
    }

    private var howToUseSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            headerIcon("questionmark.circle.fill", title: "How to Use")

            VStack(alignment: .leading, spacing: 8) {
                AccessibilityHelpRow(icon: "hand.tap.fill", title: "Tap Menu Items", description: "Tap on buttons and icons to use them.", preferences: preferences)

                Divider().background(isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.1))

                AccessibilityHelpRow(icon: "arrow.up.and.down", title: "Adjust Sliders", description: "Slide to change settings.", preferences: preferences)

                Divider().background(isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.1))

                AccessibilityHelpRow(icon: "switch.2", title: "Toggle Features", description: "Turn features on or off.", preferences: preferences)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                    .shadow(color: isDarkMode ? Color.black.opacity(0.25) : Color.black.opacity(0.1), radius: 3)
            )
        }
        .padding(.horizontal)
    }

    private var saveButton: some View {
        Button(action: saveSettings) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                Text("Save Settings")
                    .font(AppTheme.roundedFont(size: 20, weight: .bold))
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(AppTheme.adaptivePrimaryColor(preferences: preferences))
                    .shadow(color: AppTheme.adaptivePrimaryColor(preferences: preferences).opacity(0.5), radius: 5, x: 0, y: 3)
            )
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
    }

    private func headerIcon(_ systemImage: String, title: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
                .font(.system(size: 22))

            Text(title)
                .font(AppTheme.roundedFont(size: 20, weight: .semibold))
                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
        }
    }

    private var fontSizeText: String {
        switch preferences.fontSizeAdjustment {
        case -1.0 ... -0.6: return "Smallest"
        case -0.59 ... -0.2: return "Smaller"
        case -0.19 ... 0.19: return "Normal"
        case 0.2 ... 0.59: return "Larger"
        case 0.6 ... 1.0: return "Largest"
        default: return "Normal"
        }
    }

    private func playSoundTest() {
        if preferences.soundPreference != .none {
            SoundManager.shared.playSuccess()
        }
    }

    private func saveSettings() {
        guard let user = authManager.currentUser else { return }

        if preferences.soundPreference != .none {
            SoundManager.shared.playSuccess()
        }

        authManager.updateUserPreferences(for: user.id, preferences: preferences)

        withAnimation {
            showSavedMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSavedMessage = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

struct AccessibilityHelpRow: View {
    let icon: String
    let title: String
    let description: String
    let preferences: UserPreferences
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
                .font(.system(size: 18))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.roundedFont(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))
                
                Text(description)
                    .font(AppTheme.roundedFont(size: 14))
                    .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: preferences))
            }
        }
    }
}

// theme builderrr (initalise Colors w hex codes)
struct AppTheme {
    // Fonts
    static func roundedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .system(size: size, weight: weight, design: .rounded)
    }
 
    //  Core Colours (have to use american spelling)
    static let primaryColor = Color.fromHex("#FF6B6B")
    static let secondaryColor = Color.fromHex("#4ECDC4")
    static let accentColor = Color.fromHex("#FFD166")
    static let backgroundColor = Color.fromHex("#F9F9FB")
    static let cardBackground = Color.white.opacity(0.95)
    static let successColor = Color.fromHex("#06D6A0")
    static let warningColor = Color.fromHex("#FFD166")
    static let errorColor = Color.fromHex("#FF6B6B")

    // Dark Mode Colours
    static let primaryColorDark = Color.fromHex("#FF8A8A")
    static let secondaryColorDark = Color.fromHex("#64FFE3")
    static let accentColorDark = Color.fromHex("#FFE066")
    static let backgroundColorDark = Color.fromHex("#2A2D45")
    static let successColorDark = Color.fromHex("#00FA9A")
    static let errorColorDark = Color.fromHex("#FF8888")

    // Fun Extras
    static let happyCharacters = ["🦊", "🐰", "🐶", "🐱"]
    static let rewardStickers = ["⭐️", "🎉", "🏆", "🧸", "🍭"]
    static let funPurple = Color.fromHex("#9B5DE5")
    static let funPink = Color.fromHex("#F15BB5")
    static let funBlue = Color.fromHex("#00BBF9")
    static let funGreen = Color.fromHex("#00F5D4")
    static let funOrange = Color.fromHex("#FEA82F")

    static func randomFunColor() -> Color {
        let funColors = [funPurple, funPink, funBlue, funGreen, funOrange, primaryColor, secondaryColor]
        return funColors.randomElement() ?? funPurple
    }

    // adaptive Colour functions (for user modifications)
    static func adaptiveBackgroundColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? backgroundColorDark : Color.fromHex("#F5FAFF")
    }

    static func adaptiveCardBackgroundColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? Color.fromHex("#3D3D6B") : Color.white
    }

    static func adaptivePrimaryColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? primaryColorDark : primaryColor
    }

    static func adaptiveSecondaryColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? secondaryColorDark : secondaryColor
    }

    static func adaptiveTextColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? .white : .black
    }

    static func adaptiveSecondaryTextColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? Color.white.opacity(0.8) : Color.gray.opacity(0.9)
    }

    static func adaptiveAccentColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? accentColorDark : Color.pink
    }

    static func adaptiveSuccessColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? successColorDark : successColor
    }

    static func adaptiveErrorColor(preferences: UserPreferences?) -> Color {
        preferences?.visualPreference == .darkMode ? errorColorDark : errorColor
    }
}

// Helper function for progress Colou rs
func progressColor(_ value: Double) -> Color {
    if value >= 85 { return .green }        // success
    else if value >= 70 { return .yellow }  // almost there
    else if value >= 50 { return .blue }    // try again
    else { return .red }                    // needs improvement
}

// user auth models w user preference
// enum definitions (dashboardscreen n timeframe lower down)
enum UserRole: String, Codable, Equatable {
    case student
    case teacher
}

enum VisualPreference: String, Codable {
    case lightMode
    case darkMode
    case reducedMotion
}

enum SoundPreference: String, Codable {
    case all
    case feedback
    case none
}

enum SidebarItem: Hashable {
    case home
    case allLetters
    case focusMode
    case myRewards
    case teacherDashboard
}
enum ThemeOption: String, CaseIterable {
    case space = "Space"
    case forest = "Forest"
    case ocean = "Ocean"
    case mountain = "Mountain"
}

struct MultiLetterProgressBar: View {
    let scores: [Double?]

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = (geo.size.width - CGFloat(scores.count - 1) * 4) / CGFloat(scores.count)

            HStack(spacing: 4) {
                ForEach(0..<scores.count, id: \.self) { index in
                    Capsule()
                        .fill(ColorForScore(scores[index]))
                        .frame(width: segmentWidth, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 8)
        }
        .frame(height: 10)
    }

    func ColorForScore(_ score: Double?) -> Color {
        guard let score = score else {
            return Color.gray.opacity(0.3)
        }

        switch score {
        case ..<50: return AppTheme.funPink
        case 50..<85: return AppTheme.accentColor
        case 85..<95: return AppTheme.funGreen
        default: return AppTheme.funBlue
        }
    }
}

struct UserPreferences: Codable {
    var fontSizeAdjustment: CGFloat = 0.0
    var visualPreference: VisualPreference = .lightMode
    var preferredColorHex: String = "#5E60CE" // col stored as hex
    var characterEmoji: String = "🦊"
    var soundPreference: SoundPreference = .all
    var animationsEnabled: Bool = true

    var preferredColor: Color {
        Color.fromHex(preferredColorHex)

    }

    var useDarkMode: Bool {
        visualPreference == .darkMode
    }
}
struct User: Identifiable, Codable {
    var id: String
    var username: String
    private var hashedPassword: String // stores the hashed password
    
    var role: UserRole
    var fullName: String
    var dateOfBirth: Date
    var preferences: UserPreferences = UserPreferences()
    var averageScore: Double = 0.0
    
    enum CodingKeys: String, CodingKey {
        case id, username, hashedPassword, role, fullName, dateOfBirth, preferences
    }
    
    // make hashPassword static - doesn't need to access self
    private static func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
    
    // getter method
    func getHashedPasswordForDatabase() -> String {
        return hashedPassword
    }
    
    // store the hashed password during creation
    init(id: String, username: String, password: String, role: UserRole, fullName: String = "", dateOfBirth: Date = Date()) {
        self.id = id
        self.username = username
        self.hashedPassword = User.hashPassword(password) // Use the static method
        self.role = role
        self.fullName = fullName
        self.dateOfBirth = dateOfBirth
    }
    
    // verify entered password against the stored hash
    func verifyPassword(_ password: String) -> Bool {
        return User.hashPassword(password) == hashedPassword // Use the static method
    }
    
    // preserves user data (including hashed password)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(hashedPassword, forKey: .hashedPassword)
        try container.encode(role == .teacher ? "teacher" : "student", forKey: .role)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(dateOfBirth, forKey: .dateOfBirth)
        try container.encode(preferences, forKey: .preferences)
    }
    
    // decode user data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        hashedPassword = try container.decode(String.self, forKey: .hashedPassword)
        let roleString = try container.decode(String.self, forKey: .role)
        role = roleString == "teacher" ? .teacher : .student
        fullName = try container.decode(String.self, forKey: .fullName)
        dateOfBirth = try container.decode(Date.self, forKey: .dateOfBirth)
        
        // add backwards compatibility for users without preferences
        if container.contains(.preferences) {
            preferences = try container.decode(UserPreferences.self, forKey: .preferences)
        } else {
            preferences = UserPreferences()
        }
    }
}

// includes student performane data w visual rewards
struct LetterPerformance: Identifiable, Codable {
    var id = UUID()
    var letter: String
    var scores: [Double] // store multiple scores for trending
    var attempts: Int
    var lastPracticed: Date
    var userId: String = ""
    var rewards: [String] = [] // stickers/rewards collected for this letter
    var previousAverage: Double? = nil
    
    var averageScore: Double {
        scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }
    
    // check if letter is mastered (over 85% score)
    var isMastered: Bool {
        averageScore >= 85 && attempts >= 3
    }
}

class AuthManager: ObservableObject {
    // published properties
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var students: [User] = []
    @Published var teachers: [User] = []
    @Published var users: [User] = []
    @Published var currentPerformance: StudentPerformance?

    // Constants
    private let userDefaultsKey = "TracingAppUsers"
    private var database: OpaquePointer? {
        return SQLiteManager.shared.database
    }

    init() {
        SoundManager.shared.preloadSounds()

        // Temporary for dev
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        currentUser = nil
        isAuthenticated = false

        loadUsers()

        if students.isEmpty && teachers.isEmpty {
            createDefaultUsers()
        }
    }

    // user management
    func loadUsers() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            do {
                let decoder = JSONDecoder()
                let allUsers = try decoder.decode([User].self, from: data)
                students = allUsers.filter { $0.role == .student }
                teachers = allUsers.filter { $0.role == .teacher }
            } catch {
                print("Error loading users: \(error)")
            }
        }
    }

    func saveUsers() {
        let allUsers = students + teachers
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(allUsers)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("Error saving users: \(error)")
        }
    }

    // authenticationnnn
    func login(username: String, password: String) -> Bool {
        let allUsers = students + teachers
        if let user = allUsers.first(where: { $0.username == username && $0.verifyPassword(password) }) {
            SoundManager.shared.playSuccess()
            currentUser = user
            isAuthenticated = true
            loadStudentPerformanceIfNeeded()
            return true
        }
        SoundManager.shared.playError()
        return false
    }

    func logout() {
        SoundManager.shared.playClick()
        currentUser = nil
        currentPerformance = nil
        isAuthenticated = false
    }

    func registerStudent(username: String, password: String, fullName: String, dateOfBirth: Date) -> Bool {
        let allUsers = students + teachers
        if allUsers.contains(where: { $0.username == username }) {
            SoundManager.shared.playError()
            return false
        }

        var newStudent = User(
            id: UUID().uuidString,
            username: username,
            password: password,
            role: .student,
            fullName: fullName,
            dateOfBirth: dateOfBirth
        )
        newStudent.preferences.characterEmoji = AppTheme.happyCharacters.randomElement() ?? "🦊"

        students.append(newStudent)

        SQLiteManager.shared.saveStudentPerformance(
            id: newStudent.id,
            name: fullName,
            totalRewards: 0,
            streak: 0,
            lastPracticeDate: Date()
        )

        saveUsers()
        SoundManager.shared.playSuccess()
        return true
    }
    
    // student performance
    func loadStudentPerformance(for studentId: String) -> StudentPerformance? {
        guard let basic = getStudentPerformance(for: studentId) else {
            return nil
        }

        let letters = getLetterPerformances(for: studentId)
        let letterPerformances = letters.map { key, value in
            LetterPerformance(
                letter: key,
                scores: value.scores,
                attempts: value.attempts,
                lastPracticed: value.lastPracticed ?? Date.distantPast,
                rewards: value.rewards
            )
        }

        return StudentPerformance(
            id: studentId,
            studentName: basic.name,
            letterPerformances: letterPerformances,
            totalRewards: basic.totalRewards,
            consecutiveDayStreak: basic.streak,
            lastPracticeDate: basic.lastPracticeDate
        )
    }
    
    // sqlite helper methods
    func getStudentPerformance(for studentId: String) -> (name: String, totalRewards: Int, streak: Int, lastPracticeDate: Date)? {
        return SQLiteManager.shared.getStudentPerformance(for: studentId)
    }
    
    func getLetterPerformances(for studentId: String) -> [String: (scores: [Double], attempts: Int, lastPracticed: Date?, rewards: [String])] {
        return SQLiteManager.shared.getLetterPerformances(for: studentId)
    }
    
    // implementation for getting all scores
    func getAllSQLiteScores() -> [String: [String: Double?]] {
        return SQLiteManager.shared.getAllScores()
    }
    
    // implementation for getting student scores
    func getStudentSQLiteScores(for studentId: String) -> [String: Double?] {
        return SQLiteManager.shared.getUserScores(userId: studentId)
    }

    // sqlite sync
    func loadStudentPerformanceIfNeeded() {
        guard let user = currentUser, user.role == .student else { return }
        
        if let performance = getStudentPerformanceFromSQLite(for: user.id) {
            currentPerformance = performance
        } else {
            // create one and set default performance if no record
            SQLiteManager.shared.saveStudentPerformance(
                id: user.id,
                name: user.fullName.isEmpty ? user.username : user.fullName,
                totalRewards: 0,
                streak: 0,
                lastPracticeDate: Date()
            )
            
            currentPerformance = StudentPerformance(
                id: user.id,
                studentName: user.fullName,
                letterPerformances: [],
                totalRewards: 0,
                consecutiveDayStreak: 0,
                lastPracticeDate: Date()
            )
        }
    }
    
    func refreshCurrentPerformance(for studentId: String) {
        if let updated = getStudentPerformanceFromSQLite(for: studentId) {
            self.currentPerformance = updated
        }
    }

    func updateUserPreferences(for userId: String, preferences: UserPreferences) {
        if let index = students.firstIndex(where: { $0.id == userId }) {
            students[index].preferences = preferences
            if currentUser?.id == userId {
                currentUser?.preferences = preferences
            }
        }

        if let index = teachers.firstIndex(where: { $0.id == userId }) {
            teachers[index].preferences = preferences
            if currentUser?.id == userId {
                currentUser?.preferences = preferences
            }
        }

        saveUsers()
    }
    
    // performance updates
    func updateStudentPerformance(studentId: String, letter: String, score: Double) {
        // update the performance score and letter performance in the database
        PerformanceManager.shared.awardRewards(for: letter, with: score, to: studentId)
        PerformanceManager.shared.updateStreak(for: studentId)
    }
    
    func updateStudentPerformanceWithSQLite(studentId: String, letter: String, score: Double) {
        // save the score in the legacy format
        SQLiteManager.shared.saveLetterScore(userId: studentId, letter: letter, score: score)
        
        // save in new format with no rewards
        SQLiteManager.shared.saveLetterPerformance(
            userId: studentId,
            letter: letter,
            newScore: score,
            newRewards: []
        )
        
        // Update the current performance if this is the current user
        if currentUser?.id == studentId {
            refreshCurrentPerformance(for: studentId)
        }
    }
    
    func getWeakestLetters(for studentId: String, count: Int = 5) -> [LetterPerformance] {
        guard let performance = currentPerformance else { return [] }

        let weakest = performance.letterPerformances
            .filter { $0.attempts > 0 } // only consider letters that have been attempted
            .sorted { ($0.averageScore ?? 0) < ($1.averageScore ?? 0) } // sort by lowest score
            .prefix(count) // take the requested number of items
        
        return Array(weakest)
    }
    
    func getStudentStreak(for studentId: String) -> Int? {
        guard let db = database else { return nil }

        let query = "SELECT consecutiveDayStreak FROM StudentPerformance WHERE id = ?"
        var statement: OpaquePointer? = nil
        var streak: Int?

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (studentId as NSString).utf8String, -1, nil)

            if sqlite3_step(statement) == SQLITE_ROW {
                streak = Int(sqlite3_column_int(statement, 0))
            }
        }

        sqlite3_finalize(statement)
        return streak
    }
    
    func getStudentPerformanceFromSQLite(for studentId: String) -> StudentPerformance? {
        guard let db = database else { return nil }

        var studentName = "Student"
        var totalRewards = 0
        var lastPractice = Date.distantPast
        var streak = 0
        
//using paper 2 logic lol
        let infoQuery = """
        SELECT studentName, totalRewards, lastPracticeDate, consecutiveDayStreak
        FROM StudentPerformance
        WHERE id = ?;
        """
// some code borrowed (reference)
        
        var infoStmt: OpaquePointer? = nil
        if sqlite3_prepare_v2(db, infoQuery, -1, &infoStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(infoStmt, 1, (studentId as NSString).utf8String, -1, nil)
            if sqlite3_step(infoStmt) == SQLITE_ROW {
                if let nameCStr = sqlite3_column_text(infoStmt, 0) {
                    studentName = String(cString: nameCStr)
                }
                totalRewards = Int(sqlite3_column_int(infoStmt, 1))
                if let dateCStr = sqlite3_column_text(infoStmt, 2) {
                    let dateStr = String(cString: dateCStr)
                    lastPractice = ISO8601DateFormatter().date(from: dateStr) ?? .distantPast
                }
                streak = Int(sqlite3_column_int(infoStmt, 3))
            }
            sqlite3_finalize(infoStmt)
        } else {
            print("❌ Failed to prepare statement for student performance.")
            return nil
        }

        var letterPerformances: [LetterPerformance] = []
        let letters = (65...90).compactMap { UnicodeScalar($0) }.map { String($0) }

        for letter in letters {
            let scoreQuery = "SELECT scores, attempts, lastPracticed, rewards FROM LetterPerformance WHERE userid = ? AND letter = ?"
            var scoreStmt: OpaquePointer?

            if sqlite3_prepare_v2(db, scoreQuery, -1, &scoreStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(scoreStmt, 1, (studentId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(scoreStmt, 2, (letter as NSString).utf8String, -1, nil)

                if sqlite3_step(scoreStmt) == SQLITE_ROW {
                    var scores: [Double] = []
                    var attempts = 0
                    var lastPracticed: Date? = nil
                    var rewards: [String] = []

                    if let scoresData = sqlite3_column_text(scoreStmt, 0) {
                        let scoresStr = String(cString: scoresData)
                        scores = (try? JSONDecoder().decode([Double].self, from: Data(scoresStr.utf8))) ?? []
                    }

                    attempts = Int(sqlite3_column_int(scoreStmt, 1))

                    if let dateData = sqlite3_column_text(scoreStmt, 2) {
                        let dateStr = String(cString: dateData)
                        lastPracticed = ISO8601DateFormatter().date(from: dateStr)
                    }

                    if let rewardsData = sqlite3_column_text(scoreStmt, 3) {
                        let rewardsStr = String(cString: rewardsData)
                        rewards = (try? JSONDecoder().decode([String].self, from: Data(rewardsStr.utf8))) ?? []
                    }

                    let previousAvg = attempts > 1
                        ? (scores.reduce(0, +) - scores.last!) / Double(attempts - 1)
                        : nil

                    letterPerformances.append(LetterPerformance(
                        letter: letter,
                        scores: scores,
                        attempts: attempts,
                        lastPracticed: lastPracticed ?? Date.distantPast,
                        userId: studentId,
                        rewards: rewards,
                        previousAverage: previousAvg
                    ))
                } else {
                    // if letter has never been practiced
                    letterPerformances.append(LetterPerformance(
                        letter: letter,
                        scores: [],
                        attempts: 0,
                        lastPracticed: .distantPast,
                        userId: studentId,
                        rewards: [],
                        previousAverage: nil
                    ))
                }

                sqlite3_finalize(scoreStmt)
            } else {
                print("❌ Failed to prepare letter score query for letter \(letter)")
            }
        }

        return StudentPerformance(
            id: studentId,
            studentName: studentName,
            letterPerformances: letterPerformances,
            totalRewards: totalRewards,
            consecutiveDayStreak: streak,
            lastPracticeDate: lastPractice
        )
    }

    // default users
    private func createDefaultUsers() {
        let teacher = User(
            id: UUID().uuidString,
            username: "teacher",
            password: "password",
            role: .teacher,
            // my client
            fullName: "Ms. Price"
        )
        teachers.append(teacher)
        
// for demos
        let sampleStudents = [
            // random allocations of people ik
            // own account made
            User(id: UUID().uuidString, username: "yasming", password: "password", role: .student, fullName: "Yasmin Gunes", dateOfBirth: Calendar.current.date(byAdding: .year, value: -7, to: Date())!),
            User(id: UUID().uuidString, username: "abdulboss237", password: "password", role: .student, fullName: "Abdul Goldman", dateOfBirth: Calendar.current.date(byAdding: .year, value: -6, to: Date())!),
            User(id: UUID().uuidString, username: "szymong", password: "password", role: .student, fullName: "Szymon Shah", dateOfBirth: Calendar.current.date(byAdding: .year, value: -8, to: Date())!),
            User(id: UUID().uuidString, username: "simplewood", password: "password", role: .student, fullName: "Kishal Jojo", dateOfBirth: Calendar.current.date(byAdding: .year, value: -8, to: Date())!)

        ]

        for var student in sampleStudents {
            student.preferences.characterEmoji = AppTheme.happyCharacters.randomElement() ?? "🦊"
            students.append(student)
            SQLiteManager.shared.saveStudentPerformance(
                id: student.id,
                name: student.fullName,
                totalRewards: 0,
                streak: 0,
                lastPracticeDate: Date()
            )
        }

        saveUsers()
    }
}

// the export code was
class ExportHelper {
    private static let tempDir = FileManager.default.temporaryDirectory

    static func exportCSV(_ performances: [StudentPerformance], fileName: String = "StudentPerformance_Report.csv") {
        var text = "Student Name,Letter,Score,Attempts,Last Practiced\n"
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .none
        performances.forEach { student in
            student.letterPerformances
                .sorted { $0.letter < $1.letter }
                .forEach { lp in
                    let date = df.string(from: lp.lastPracticed)
                    let row = [
                        student.studentName,
                        lp.letter,
                        String(format: "%.1f", lp.averageScore),
                        "\(lp.attempts)",
                        date
                    ]
                    text += row.joined(separator: ",") + "\n"
                }
        }
        if let data = text.data(using: .utf8) {
            save(data, name: fileName, type: .commaSeparatedText)
        }
    }
// output formats for teacher dashboard stuff
    static func exportCSV(_ perf: StudentPerformance, fileName: String? = nil) {
        let name = fileName ?? "\(perf.studentName.replacingOccurrences(of: " ", with: "_"))_Performance.csv"
        var text = "Letter,Average Score,Attempts,Last Practiced\n"
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .none
        perf.letterPerformances
            .sorted { $0.letter < $1.letter }
            .forEach { lp in
                let date = df.string(from: lp.lastPracticed)
                let row = [
                    lp.letter,
                    String(format: "%.1f", lp.averageScore),
                    "\(lp.attempts)",
                    date
                ]
                text += row.joined(separator: ",") + "\n"
            }
        if let data = text.data(using: .utf8) {
            save(data, name: name, type: .commaSeparatedText)
        }
    }

    static func exportAllStudentsCSV(using auth: AuthManager) async {
        var text = "Name,Username,Streak,Total Rewards,Last Practice,Weakest Letters,Alphabet Average,Total Attempts\n"
        let iso = ISO8601DateFormatter()
        auth.students.forEach { student in
            guard let perf = auth.getStudentPerformanceFromSQLite(for: student.id) else { return }
            let name = student.fullName.isEmpty ? student.username : student.fullName
            let streak = perf.consecutiveDayStreak
            let rewards = perf.totalRewards
            let last = iso.string(from: perf.lastPracticeDate)
            let totalAttempts = perf.letterPerformances.map { $0.attempts }.reduce(0, +)
            let weakest = totalAttempts == 0
                ? "Hasn't practiced yet"
                : perf.lettersNeedingImprovement.prefix(6).map { $0.letter }.joined(separator: " ")
            let avg = Int(perf.overallAverage)
            let row = [
                name, student.username,
                "\(streak)", "\(rewards)",
                last, weakest,
                "\(avg)", "\(totalAttempts)"
            ]
            text += row.joined(separator: ",") + "\n"
        }
        if let data = text.data(using: .utf8) {
            save(data, name: "AllStudents_Report.csv", type: .commaSeparatedText)
        }
    }

    static func exportAllStudentsPDF(using auth: AuthManager) async {
        let url = tempDir.appendingPathComponent("AllStudents_Report.pdf")
        let meta = [
            kCGPDFContextCreator as String: "Inkspire",
            kCGPDFContextAuthor as String: "Teacher Export",
            kCGPDFContextTitle as String: "All Students Report"
        ]
        let format = UIGraphicsPDFRendererFormat(); format.documentInfo = meta
        let rect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: rect, format: format)
        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = 20
            "All Students Report".draw(at: CGPoint(x: 20, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
            y += 36
            let cols = ["Name","Username","Streak","Rewards","Last Practice","Weakest Letters","Avg","Attempts"]
            let widths: [CGFloat] = [100, 80, 40, 50, 90, 130, 30, 55]
            var x: CGFloat = 20
            let f = UIFont.systemFont(ofSize: 12)
            cols.enumerated().forEach { i, title in
                title.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: f])
                x += widths[i] + 8
            }
            y += 22
            auth.students.forEach { student in
                guard let perf = auth.getStudentPerformanceFromSQLite(for: student.id) else { return }
                let name = student.fullName.isEmpty ? student.username : student.fullName
                let streak = "\(perf.consecutiveDayStreak)"
                let rewards = "\(perf.totalRewards)"
                let last = DateFormatter.localizedString(from: perf.lastPracticeDate, dateStyle: .short, timeStyle: .none)
                let attempts = perf.letterPerformances.map({ $0.attempts }).reduce(0, +)
                let weakest = attempts == 0
                    ? "Hasn't practiced yet"
                    : perf.lettersNeedingImprovement.prefix(6).map { $0.letter }.joined(separator: " ")
                let avg = "\(Int(perf.overallAverage))"
                let row = [name, student.username, streak, rewards, last, weakest, avg, "\(attempts)"]
                x = 20
                row.enumerated().forEach { i, text in
                    text.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: f])
                    x += widths[i] + 8
                }
                y += 22
                if y > rect.height - 20 { ctx.beginPage(); y = 20 }
            }
        }
        present(url)
    }

    @MainActor
    static func exportViewAsPDF<V: View>(_ view: V, fileName: String) async {
        let renderer = ImageRenderer(content: view)
        guard let img = await renderer.uiImage else { return }
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var box = CGRect(origin: .zero, size: img.size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
        ctx.beginPDFPage(nil)
        ctx.draw(img.cgImage!, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
        save(data as Data, name: "\(fileName).pdf", type: .pdf)
    }

    @MainActor
    static func exportViewAsImage<V: View>(_ view: V, fileName: String = "Snapshot.png") {
        let renderer = ImageRenderer(content: view)
        guard let img = renderer.uiImage, let data = img.pngData() else { return }
        save(data, name: fileName, type: .png)
    }

    private static func save(_ data: Data, name: String, type: UTType) {
        let url = tempDir.appendingPathComponent(name)
        do { try data.write(to: url); present(url) } catch {}
    }

    private static func present(_ url: URL) {
        DispatchQueue.main.async {
            let picker = UIDocumentPickerViewController(forExporting: [url])
            UIApplication.shared.windows.first?.rootViewController?.present(picker, animated: true)
        }
    }
}


// path segment for animating with pen lifts
// 'pen lifts' og updated bc of letters like A etc
struct PathSegment {
    var points: [CGPoint] // points in this continuous segment
    var isNewStroke: Bool // is this the start of a new stroke (pen lifted before this)
}

// Arrow data structure
struct ArrowPathData: Identifiable {
    var id: Int
    var start: CGPoint
    var end: CGPoint
}
// Arrow shape
struct ArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var arrowSize: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Draw line
        path.move(to: start)
        path.addLine(to: end)
        
        // Calculate arrow head
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowAngle1 = angle + .pi * 0.75
        let arrowAngle2 = angle - .pi * 0.75
        
        let arrowPoint1 = CGPoint(
            x: end.x + arrowSize * cos(arrowAngle1),
            y: end.y + arrowSize * sin(arrowAngle1)
        )
        
        let arrowPoint2 = CGPoint(
            x: end.x + arrowSize * cos(arrowAngle2),
            y: end.y + arrowSize * sin(arrowAngle2)
        )
        
        // Draw arrow head
        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)
        
        return path
    }
}

struct EnhancedArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var arrowSize: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Draw line
        path.move(to: start)
        path.addLine(to: end)
        
        // Calculate arrow head
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowAngle1 = angle + .pi * 0.75
        let arrowAngle2 = angle - .pi * 0.75
        
        let arrowPoint1 = CGPoint(
            x: end.x + arrowSize * cos(arrowAngle1),
            y: end.y + arrowSize * sin(arrowAngle1)
        )
        
        let arrowPoint2 = CGPoint(
            x: end.x + arrowSize * cos(arrowAngle2),
            y: end.y + arrowSize * sin(arrowAngle2)
        )
        
        // Draw arrow head
        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)
        
        return path
    }
}

// tracing path definition
// old code but included in some other stuff so i left it bc i cba
struct TracingPathDefinition {
    var path: (CGRect) -> Path
    var guidePoints: (CGSize) -> [CGPoint]
    var arrowPaths: (CGSize) -> [ArrowPathData]
    
    // define the reference points for scoring
    // dense set of points along the path created
    func referencePoints(in rect: CGRect, pointCount: Int = 100) -> [CGPoint] {
        let fullPath = path(rect)
        let bezierPath = UIBezierPath(cgPath: fullPath.cgPath)
        var points: [CGPoint] = []
        
        // sample points along the entire path
        for i in 0...pointCount {
            let t = CGFloat(i) / CGFloat(pointCount)
            points.append(bezierPath.point(at: t))
        }
        
        return points
    }
}

// enhanced tracing path definition (more accurate)
struct EnhancedTracingPathDefinition {
    var path: (CGRect) -> Path
    var guidePoints: (CGSize) -> [CGPoint]
    var arrowPaths: (CGSize) -> [ArrowPathData]
    var strokeSegments: (CGSize) -> [PathSegment] //(only new inclusion)

    func referencePoints(in rect: CGRect, pointCount: Int = 100) -> [CGPoint] {
        let fullPath = path(rect)
        let bezierPath = UIBezierPath(cgPath: fullPath.cgPath)
        var points: [CGPoint] = []
        
        // sample points along the entire path
        // same as ^^
        for i in 0...pointCount {
            let t = CGFloat(i) / CGFloat(pointCount)
            points.append(bezierPath.point(at: t))
        }
        
        return points
    }
}
    
// tracing path view
struct TracingPathView: Shape {
    var letter: String
    
    func path(in rect: CGRect) -> Path {
        return LetterPathFactory.letterPathDefinition(for: letter).path(rect)
    }
}

struct EnhancedTracingAnimatedPathView: View {
    var letter: String
    var progress: CGFloat // 0.0 to 1.0
    
    var body: some View {
        GeometryReader { geometry in
            if let enhancedPathDef = EnhancedLetterPathFactory.getEnhancedLetterPath(for: letter) {
                // use enhanced path with segments for pen lifting
                EnhancedPathView(
                    letter: letter,
                    progress: progress,
                    enhancedPathDef: enhancedPathDef,
                    size: geometry.size
                )
            } else {
                // fallback to original path for letters without pen lifting
                TracingAnimatedPathView(
                    letter: letter,
                    progress: progress
                )
            }
        }
    }
}

struct EnhancedPathView: View {
    var letter: String
    var progress: CGFloat
    var enhancedPathDef: EnhancedTracingPathDefinition
    var size: CGSize
    
    var body: some View {
        ZStack {
            // Get segments
            let segments = enhancedPathDef.strokeSegments(size)
            
            // Calculate how many segments to show based on progress
            let totalSegments = segments.count
            let segmentSize = 1.0 / CGFloat(totalSegments)
            
            // For each segment, determine if it should be drawn and how much of it
            ForEach(0..<segments.count, id: \.self) { index in
                let segmentStartProgress = CGFloat(index) * segmentSize
                
                // If we've reached this segment
                if progress >= segmentStartProgress {
                    let segmentProgress = min(1.0, (progress - segmentStartProgress) / segmentSize)
                    
                    // Draw segment with appropriate progress
                    SegmentPathView(
                        points: segments[index].points,
                        progress: segmentProgress
                    )
                    .stroke(AppTheme.secondaryColor, lineWidth: 6)
                    .shadow(color: AppTheme.secondaryColor.opacity(0.5), radius: 2)
                }
            }
        }
    }
}

// animated path for sample tracing for student
struct TracingAnimatedPathView: Shape {
    var letter: String
    var progress: CGFloat // 0.0 to 1.0
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        // get the complete path
        let fullPath = LetterPathFactory.letterPathDefinition(for: letter).path(rect)
        
        // Create a trimmed path based on progress
        return trimmedPath(from: fullPath, to: progress)
    }
    
    private func trimmedPath(from originalPath: Path, to percentage: CGFloat) -> Path {
        let cgPath = originalPath.cgPath
        
        // Convert to a UIBezierPath for easier trimming
        let bezierPath = UIBezierPath(cgPath: cgPath)
        
        // If progress is 0, return empty path
        if percentage <= 0 {
            return Path()
        }
        
        // If progress is 1, return full path
        if percentage >= 1 {
            return originalPath
        }
        
        // Create a new path to hold our trimmed path
        let trimmedPath = UIBezierPath()
        var isFirstPoint = true
        
        // Sample points along the path at the right percentage
        let pointCount = 100
        for i in 0...pointCount {
            let t = CGFloat(i) / CGFloat(pointCount)
            
            if t <= percentage {
                let point = bezierPath.point(at: t)
                
                if isFirstPoint {
                    trimmedPath.move(to: point)
                    isFirstPoint = false
                } else {
                    trimmedPath.addLine(to: point)
                }
            }
        }
        
        return Path(trimmedPath.cgPath)
    }
}

// fun characters to boost engagement
// keeping up w the emoji theme based on gizmo flashcard app bc i find that fun

struct AnimatedCharacter: View {
    let character: String
    @State private var scale: CGFloat = 1.0
    @State private var rotation: Double = 0
    let isAnimating: Bool
    
    var body: some View {
        Text(character)
            .font(.system(size: 60))
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                if isAnimating {
                    withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        self.scale = 1.2
                    }
                    withAnimation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        self.rotation = 5
                    }
                }
            }
    }
}
    
// added 'expressions'
// didnt rlly implement but kept code jic
struct ExpressiveCharacter: View {
    let emoji: String
    let expression: Expression
    @State private var scale: CGFloat = 1.0
    @State private var bounceOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    
    enum Expression {
        case neutral, happy, excited, thinking
    }
    
    var body: some View {
        ZStack {
            // Shadow
            Circle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 65, height: 15)
                .offset(y: 40)
                .scaleEffect(x: scale)
            
            // Character
            Text(emoji)
                .font(.system(size: 60))
                .offset(y: bounceOffset)
                .rotationEffect(.degrees(wiggleAngle))
            
            // Expression indicator
            ZStack {
                Circle()
                    .fill(expressionColor)
                    .frame(width: 24, height: 24)
                
                Image(systemName: expressionIcon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .offset(x: 25, y: -20)
            .opacity(expression == .neutral ? 0 : 1)
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private var expressionColor: Color {
        switch expression {
        case .neutral: return Color.clear
        case .happy: return Color.green
        case .excited: return AppTheme.secondaryColor
        case .thinking: return AppTheme.primaryColor
        }
    }
    
    private var expressionIcon: String {
        switch expression {
        case .neutral: return ""
        case .happy: return "heart.fill"
        case .excited: return "star.fill"
        case .thinking: return "bubble.left.fill"
        }
    }
    
    private func startAnimation() {
        switch expression {
        case .neutral:
            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                bounceOffset = -5
            }
        case .happy:
            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                bounceOffset = -8
                scale = 1.1
            }
        case .excited:
            // Faster, more energetic bounce
            withAnimation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                bounceOffset = -10
                scale = 1.15
            }
            // Add wiggle
            withAnimation(Animation.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                wiggleAngle = 5
            }
        case .thinking:
            // tilting
            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                wiggleAngle = 5
                bounceOffset = -3
            }
        }
    }
}
// to make tracing more accessible
struct NumberedPathGuideView: View {
    var letter: String
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // get the guide points for the letter from my other structs
                let guidePoints = LetterPathFactory.letterPathDefinition(for: letter).guidePoints(geometry.size)
                ForEach(guidePoints.indices, id: \.self) { index in
                    let point = guidePoints[index]
                    
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 22, height: 22)
                        
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    .position(point)
                }
            }
        }
    }
}

struct EnhancedNumberedPathGuideView: View {
    var letter: String
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Get the guide points for the letter
                let guidePoints = LetterPathFactory.letterPathDefinition(for: letter).guidePoints(geometry.size)
                ForEach(guidePoints.indices, id: \.self) { index in
                    let point = guidePoints[index]
                    
                    ZStack {
                        // Outer circle
                        Circle()
                            .fill(AppTheme.primaryColor.opacity(0.2))
                            .frame(width: 32, height: 32)
                        
                        // Inner circle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 26, height: 26)
                            .shadow(Color: AppTheme.primaryColor.opacity(0.5), radius: 2)
                        
                        // Number
                        Text("\(index + 1)")
                            .font(AppTheme.roundedFont(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.primaryColor)
                    }
                    .position(point)
                }
            }
        }
    }
}
struct DirectionalArrowsView: View {
    enum Style {
        case basic, enhanced
    }

    var letter: String
    var style: Style = .enhanced

    private var arrowSize: CGFloat {
        style == .enhanced ? 14 : 12
    }
    private var strokeColor: Color {
        style == .enhanced ? AppTheme.secondaryColor : .orange
    }
    private var lineWidth: CGFloat {
        style == .enhanced ? 3 : 2.5
    }
    private var opacityValue: Double {
        style == .enhanced ? 1 : 0.8
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Fetch arrow paths for the specified letter and size
                let arrowPaths = LetterPathFactory
                    .letterPathDefinition(for: letter)
                    .arrowPaths(geometry.size)

                ForEach(arrowPaths, id: \.id) { arrowData in
                    if style == .enhanced {
                        EnhancedArrowShape(
                            start: arrowData.start,
                            end: arrowData.end,
                            arrowSize: arrowSize
                        )
                        .stroke(strokeColor, lineWidth: lineWidth)
                        .shadow(color: strokeColor.opacity(0.5), radius: 1)
                    } else {
                        ArrowShape(
                            start: arrowData.start,
                            end: arrowData.end,
                            arrowSize: arrowSize
                        )
                        .stroke(strokeColor, lineWidth: lineWidth)
                        .opacity(opacityValue)
                    }
                }
            }
        }
    }
}


// 'factory' - each letter is defined with a path i drew w mapping different points doing trial and error
// ^ hence didnt include lowercase bc thats too difficult lol
// curved letters later adjusted for

struct LetterPathFactory {
    static func letterPathDefinition(for letter: String) -> TracingPathDefinition {
        switch letter {
        case "A":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Left diagonal stroke
                    path.move(to: CGPoint(x: width * 0.2, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.2))
                    
                    // Right diagonal stroke
                    path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.8))
                    
                    // Horizontal line
                    path.move(to: CGPoint(x: width * 0.35, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.5))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.2, y: height * 0.8),  // Bottom left
                        CGPoint(x: width * 0.5, y: height * 0.2),  // Top middle
                        CGPoint(x: width * 0.8, y: height * 0.8),  // Bottom right
                        CGPoint(x: width * 0.35, y: height * 0.5), // Left middle (horizontal line start)
                        CGPoint(x: width * 0.65, y: height * 0.5)  // Right middle (horizontal line end)
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left diagonal arrows
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.2, y: height * 0.8),
                            end: CGPoint(x: width * 0.35, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.35, y: height * 0.5),
                            end: CGPoint(x: width * 0.5, y: height * 0.2)
                        ),
                        
                        // Right diagonal arrows
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.65, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.65, y: height * 0.5),
                            end: CGPoint(x: width * 0.8, y: height * 0.8)
                        ),
                        
                        // Horizontal line arrow
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.35, y: height * 0.5),
                            end: CGPoint(x: width * 0.65, y: height * 0.5)
                        )
                    ]
                }
            )
        case "B":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                                            
                    // Vertical line
                    path.move(to: CGPoint(x: width * 0.3, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.8))
                                            
                    // Top loop - (more curved and less rectangular)
                    // final version
                    path.move(to: CGPoint(x: width * 0.3, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.55, y: height * 0.2))
                    path.addCurve(
                        to: CGPoint(x: width * 0.55, y: height * 0.45),
                        control1: CGPoint(x: width * 0.7, y: height * 0.2),
                        control2: CGPoint(x: width * 0.7, y: height * 0.45)
                    )
                    path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.45))
                                            
                    // Bottom loop - larger and more curved
                    path.move(to: CGPoint(x: width * 0.3, y: height * 0.45))
                    path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.45))
                    path.addCurve(
                        to: CGPoint(x: width * 0.6, y: height * 0.8),
                        control1: CGPoint(x: width * 0.75, y: height * 0.45),
                        control2: CGPoint(x: width * 0.75, y: height * 0.8)
                    )
                    path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.8))
                                            
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.3, y: height * 0.2),   // Top left
                        CGPoint(x: width * 0.55, y: height * 0.2),  // Top right
                        CGPoint(x: width * 0.65, y: height * 0.32), // 3. Top curve
                        CGPoint(x: width * 0.55, y: height * 0.45), // 4. Middle right (top loop)
                        CGPoint(x: width * 0.3, y: height * 0.45),  // 5. Middle left
                        CGPoint(x: width * 0.6, y: height * 0.45),  // 6. Middle right (bottom loop)
                        CGPoint(x: width * 0.7, y: height * 0.62),  // 7. Bottom curve
                        CGPoint(x: width * 0.6, y: height * 0.8),   // 8. Bottom right
                        CGPoint(x: width * 0.3, y: height * 0.8)    // 9. Bottom left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical line
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.3, y: height * 0.2),
                            end: CGPoint(x: width * 0.3, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.3, y: height * 0.5),
                            end: CGPoint(x: width * 0.3, y: height * 0.8)
                        ),
                                                
                        // Top horizontal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.3, y: height * 0.2),
                            end: CGPoint(x: width * 0.55, y: height * 0.2)
                        ),
                                                
                        // Top curve - adjusted for better alignment with the actual curve
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.55, y: height * 0.2),
                            end: CGPoint(x: width * 0.65, y: height * 0.25)
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.65, y: height * 0.25),
                            end: CGPoint(x: width * 0.68, y: height * 0.32)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.68, y: height * 0.32),
                            end: CGPoint(x: width * 0.65, y: height * 0.39)
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.65, y: height * 0.39),
                            end: CGPoint(x: width * 0.55, y: height * 0.45)
                        ),
                                                
                        // Middle horizontal
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.55, y: height * 0.45),
                            end: CGPoint(x: width * 0.3, y: height * 0.45)
                        ),
                                                
                        // Bottom horizontal
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.3, y: height * 0.45),
                            end: CGPoint(x: width * 0.6, y: height * 0.45)
                        ),
                                                
                        // Bottom curve - adjusted for better alignment
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.6, y: height * 0.45),
                            end: CGPoint(x: width * 0.7, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.7, y: height * 0.5),
                            end: CGPoint(x: width * 0.72, y: height * 0.62)
                        ),
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.72, y: height * 0.62),
                            end: CGPoint(x: width * 0.7, y: height * 0.72)
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.7, y: height * 0.72),
                            end: CGPoint(x: width * 0.6, y: height * 0.8)
                        ),
                                                
                        // Bottom closing horizontal
                        ArrowPathData(
                            id: 14,
                            start: CGPoint(x: width * 0.6, y: height * 0.8),
                            end: CGPoint(x: width * 0.3, y: height * 0.8)
                        )
                    ]
                }
            )
            
        case "C":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital C with proper curves
                    path.move(to: CGPoint(x: width * 0.75, y: height * 0.25))
                    
                    path.addCurve(
                        to: CGPoint(x: width * 0.3, y: height * 0.5),
                        control1: CGPoint(x: width * 0.6, y: height * 0.15),
                        control2: CGPoint(x: width * 0.3, y: height * 0.25)
                    )
                    
                    path.addCurve(
                        to: CGPoint(x: width * 0.75, y: height * 0.75),
                        control1: CGPoint(x: width * 0.3, y: height * 0.75),
                        control2: CGPoint(x: width * 0.6, y: height * 0.85)
                    )
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.75, y: height * 0.25), // 1. Top right
                        CGPoint(x: width * 0.6, y: height * 0.2),   // 2. Top curve point 1
                        CGPoint(x: width * 0.4, y: height * 0.3),   // 3. Top curve point 2
                        CGPoint(x: width * 0.3, y: height * 0.5),   // 4. Middle left
                        CGPoint(x: width * 0.4, y: height * 0.7),   // 5. Bottom curve point 1
                        CGPoint(x: width * 0.6, y: height * 0.8),   // 6. Bottom curve point 2
                        CGPoint(x: width * 0.75, y: height * 0.75)  // 7. Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Top arc - arrows raised higher, gradients adjusted
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.75, y: height * 0.26), // Raised slightly higher
                            end: CGPoint(x: width * 0.71, y: height * 0.24)    // Gradient halved (less steep)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.71, y: height * 0.24),
                            end: CGPoint(x: width * 0.6, y: height * 0.21)     // Raised slightly higher
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.6, y: height * 0.21),   // Adjusted to match arrow 2's end
                            end: CGPoint(x: width * 0.5, y: height * 0.23)      // Slightly raised
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.5, y: height * 0.23),
                            end: CGPoint(x: width * 0.4, y: height * 0.27)
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.4, y: height * 0.27),
                            end: CGPoint(x: width * 0.35, y: height * 0.32)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.35, y: height * 0.32),
                            end: CGPoint(x: width * 0.3, y: height * 0.4)       // Slightly steeper gradient
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.3, y: height * 0.4),
                            end: CGPoint(x: width * 0.3, y: height * 0.5)
                        ),
                        
                        // Bottom arc - last four arrows brought WAY lower
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.3, y: height * 0.5),
                            end: CGPoint(x: width * 0.3, y: height * 0.6)
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.3, y: height * 0.6),
                            end: CGPoint(x: width * 0.35, y: height * 0.66)
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.35, y: height * 0.66),
                            end: CGPoint(x: width * 0.4, y: height * 0.71)
                        ),
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.4, y: height * 0.71),
                            end: CGPoint(x: width * 0.5, y: height * 0.78)      // Perfect as per feedback
                        ),
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.5, y: height * 0.78),
                            end: CGPoint(x: width * 0.6, y: height * 0.79)      // Aligns with arrow 13's start
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.6, y: height * 0.79),   // Starts where arrow 12 ends
                            end: CGPoint(x: width * 0.7, y: height * 0.77)      // Even less steep (tiny bit up)
                        ),
                        ArrowPathData(
                            id: 14,
                            start: CGPoint(x: width * 0.7, y: height * 0.77),   // Starts where arrow 13 ends
                            end: CGPoint(x: width * 0.75, y: height * 0.75)     // Slightly longer, same gentle gradient
                        )
                    ]
                }
            )
        case "D":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Vertical line
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    // Top horizontal
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.45, y: height * 0.2))
                    
                    // Curved side
                    path.addCurve(
                        to: CGPoint(x: width * 0.45, y: height * 0.8),
                        control1: CGPoint(x: width * 0.75, y: height * 0.2),
                        control2: CGPoint(x: width * 0.75, y: height * 0.8)
                    )
                    
                    // Bottom horizontal
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.45, y: height * 0.2),  // Top right
                        CGPoint(x: width * 0.65, y: height * 0.35), // 3. Upper curve
                        CGPoint(x: width * 0.65, y: height * 0.65), // 4. Lower curve
                        CGPoint(x: width * 0.45, y: height * 0.8),  // Bottom right
                        CGPoint(x: width * 0.25, y: height * 0.8)   // 6. Bottom left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical line remains the same
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Top horizontal remains the same
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.45, y: height * 0.2)
                        ),
                        
                        // Curved side - rightmost curves brought the SLIGHTEST bit more inward
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.45, y: height * 0.2),
                            end: CGPoint(x: width * 0.56, y: height * 0.23) // Slight inward adjustment
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.56, y: height * 0.23),
                            end: CGPoint(x: width * 0.64, y: height * 0.3) // Slight inward adjustment
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.64, y: height * 0.3),
                            end: CGPoint(x: width * 0.68, y: height * 0.4) // Slight inward adjustment
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.68, y: height * 0.4),
                            end: CGPoint(x: width * 0.68, y: height * 0.6) // Adjusted for continuity
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.68, y: height * 0.6),
                            end: CGPoint(x: width * 0.64, y: height * 0.7) // Slight inward adjustment
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.64, y: height * 0.7),
                            end: CGPoint(x: width * 0.56, y: height * 0.77) // Slight inward adjustment
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.56, y: height * 0.77),
                            end: CGPoint(x: width * 0.45, y: height * 0.8) // Slight inward adjustment
                        ),
                        
                        // Bottom horizontal remains the same
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.45, y: height * 0.8),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        )
                    ]
                }
            )
        case "E":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital E
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.2))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.5))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.7, y: height * 0.2),   // Top right
                        CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                        CGPoint(x: width * 0.6, y: height * 0.5),   // 4. Middle right
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 5. Bottom left
                        CGPoint(x: width * 0.7, y: height * 0.8)    // 6. Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical line
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Top horizontal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.7, y: height * 0.2)
                        ),
                        
                        // Middle horizontal
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.6, y: height * 0.5)
                        ),
                        
                        // Bottom horizontal
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.25, y: height * 0.8),
                            end: CGPoint(x: width * 0.7, y: height * 0.8)
                        )
                    ]
                }
            )
        case "F":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital F
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.2))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.5))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.7, y: height * 0.2),   // Top right
                        CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                        CGPoint(x: width * 0.6, y: height * 0.5),   // 4. Middle right
                        CGPoint(x: width * 0.25, y: height * 0.8)   // 5. Bottom
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical line
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Top horizontal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.7, y: height * 0.2)
                        ),
                        
                        // Middle horizontal
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.6, y: height * 0.5)
                        )
                    ]
                }
            )
        case "G":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital G
                    path.move(to: CGPoint(x: width * 0.7, y: height * 0.3))
                    
                    path.addCurve(
                        to: CGPoint(x: width * 0.3, y: height * 0.5),
                        control1: CGPoint(x: width * 0.6, y: height * 0.15),
                        control2: CGPoint(x: width * 0.3, y: height * 0.25)
                    )
                    
                    path.addCurve(
                        to: CGPoint(x: width * 0.7, y: height * 0.7),
                        control1: CGPoint(x: width * 0.3, y: height * 0.75),
                        control2: CGPoint(x: width * 0.6, y: height * 0.85)
                    )
                    
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.55))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.55))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.7, y: height * 0.3),   // 1. Top right
                        CGPoint(x: width * 0.55, y: height * 0.2),  // 2. Top curve 1
                        CGPoint(x: width * 0.4, y: height * 0.3),   // 3. Top curve 2
                        CGPoint(x: width * 0.3, y: height * 0.5),   // 4. Middle left
                        CGPoint(x: width * 0.4, y: height * 0.7),   // 5. Bottom curve 1
                        CGPoint(x: width * 0.6, y: height * 0.8),   // 6. Bottom curve 2
                        CGPoint(x: width * 0.7, y: height * 0.7),   // 7. Bottom right
                        CGPoint(x: width * 0.7, y: height * 0.55),  // 8. Middle right
                        CGPoint(x: width * 0.5, y: height * 0.55)   // 9. Middle point
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Top curve - adjusted for less steep Arrow 2
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.72, y: height * 0.3), // Start remains unchanged
                            end: CGPoint(x: width * 0.65, y: height * 0.24)   // End remains unchanged
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.65, y: height * 0.24), // Matches Arrow 1's end
                            end: CGPoint(x: width * 0.6, y: height * 0.22)     // Less steep, brought down slightly
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.6, y: height * 0.22),  // Matches Arrow 2's end
                            end: CGPoint(x: width * 0.45, y: height * 0.24)    // Brought down slightly
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.45, y: height * 0.24), // Matches Arrow 3's end
                            end: CGPoint(x: width * 0.39, y: height * 0.29)      // Moved southeast (right + down)
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.39, y: height * 0.29),   // Matches Arrow 4's end
                            end: CGPoint(x: width * 0.32, y: height * 0.4)     // Adjusted for continuity
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.32, y: height * 0.4),
                            end: CGPoint(x: width * 0.3, y: height * 0.55)    // Vertical section
                        ),
                        
                        // Bottom curve - adjusted for continuity
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.3, y: height * 0.55),
                            end: CGPoint(x: width * 0.35, y: height * 0.65)    // Adjusted for smoothness
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.35, y: height * 0.65),
                            end: CGPoint(x: width * 0.46, y: height * 0.76)    // Adjusted for smoothness
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.46, y: height * 0.76),
                            end: CGPoint(x: width * 0.6, y: height * 0.78)     // Adjusted for smoothness
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.6, y: height * 0.78),
                            end: CGPoint(x: width * 0.68, y: height * 0.72)    // Adjusted for smoothness
                        ),
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.68, y: height * 0.72),
                            end: CGPoint(x: width * 0.72, y: height * 0.7)     // Connects to middle line
                        ),
                        
                        // Middle line - straight and clean
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.70, y: height * 0.7),
                            end: CGPoint(x: width * 0.70, y: height * 0.55)
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.72, y: height * 0.55),
                            end: CGPoint(x: width * 0.5, y: height * 0.55)
                        )
                    ]
                }
            )
        case "H":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital H
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.5))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.25, y: height * 0.5),  // 2. Middle left
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 3. Bottom left
                        CGPoint(x: width * 0.75, y: height * 0.2),  // 4. Top right
                        CGPoint(x: width * 0.75, y: height * 0.5),  // 5. Middle right
                        CGPoint(x: width * 0.75, y: height * 0.8)   // 6. Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left vertical
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Right vertical
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.75, y: height * 0.2),
                            end: CGPoint(x: width * 0.75, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.75, y: height * 0.5),
                            end: CGPoint(x: width * 0.75, y: height * 0.8)
                        ),
                        
                        // Horizontal
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.75, y: height * 0.5)
                        )
                    ]
                }
            )
        case "I":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital I
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.35, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.2))
                    
                    path.move(to: CGPoint(x: width * 0.35, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.35, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.5, y: height * 0.2),   // 2. Top center
                        CGPoint(x: width * 0.65, y: height * 0.2),  // 3. Top right
                        CGPoint(x: width * 0.5, y: height * 0.5),   // 4. Middle
                        CGPoint(x: width * 0.35, y: height * 0.8),  // 5. Bottom left
                        CGPoint(x: width * 0.5, y: height * 0.8),   // 6. Bottom center
                        CGPoint(x: width * 0.65, y: height * 0.8)   // 7. Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Top horizontal
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.35, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.2)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.65, y: height * 0.2)
                        ),
                        
                        // Vertical
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        ),
                        
                        // Bottom horizontal
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.35, y: height * 0.8),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.5, y: height * 0.8),
                            end: CGPoint(x: width * 0.65, y: height * 0.8)
                        )
                    ]
                }
            )
        case "J":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital J
                    path.move(to: CGPoint(x: width * 0.65, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.6))
                    
                    path.addCurve(
                        to: CGPoint(x: width * 0.35, y: height * 0.6),
                        control1: CGPoint(x: width * 0.65, y: height * 0.8),
                        control2: CGPoint(x: width * 0.35, y: height * 0.8)
                    )
                    
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.2))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.5, y: height * 0.2),   // Top left
                        CGPoint(x: width * 0.8, y: height * 0.2),   // Top right
                        CGPoint(x: width * 0.65, y: height * 0.2),  // 3. Top center
                        CGPoint(x: width * 0.65, y: height * 0.6),  // 4. Middle right
                        CGPoint(x: width * 0.5, y: height * 0.75),  // 5. Bottom curve
                        CGPoint(x: width * 0.35, y: height * 0.6)   // 6. Bottom left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Top horizontal remains the same
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.65, y: height * 0.2)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.65, y: height * 0.2),
                            end: CGPoint(x: width * 0.8, y: height * 0.2)
                        ),
                        
                        // Vertical remains the same
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.65, y: height * 0.2),
                            end: CGPoint(x: width * 0.65, y: height * 0.6)
                        ),
                        
                        // Curve with more segments
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.65, y: height * 0.6),
                            end: CGPoint(x: width * 0.62, y: height * 0.7) // Start of curve
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.62, y: height * 0.7),
                            end: CGPoint(x: width * 0.58, y: height * 0.74) // Reduced gradient (less steep)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.58, y: height * 0.74), // Matches Arrow 5's end
                            end: CGPoint(x: width * 0.51, y: height * 0.76)    // Slight downward diagonal
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.51, y: height * 0.76), // Matches Arrow 6's end
                            end: CGPoint(x: width * 0.45, y: height * 0.74)    // Slight upward diagonal
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.45, y: height * 0.74), // Matches Arrow 7's end
                            end: CGPoint(x: width * 0.38, y: height * 0.7)     // Adjusted for continuity
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.38, y: height * 0.7),
                            end: CGPoint(x: width * 0.35, y: height * 0.6)     // End of curve
                        )
                    ]
                }
            )
        case "K":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital K
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.2))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.25, y: height * 0.5),  // 2. Middle left
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 3. Bottom left
                        CGPoint(x: width * 0.7, y: height * 0.2),   // 4. Top right
                        CGPoint(x: width * 0.7, y: height * 0.8)    // Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical remains the same
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.35)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.35),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.65)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.25, y: height * 0.65),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Top diagonal simplified to one or two arrows
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.25, y: height * 0.5), // Start from middle left
                            end: CGPoint(x: width * 0.7, y: height * 0.2)     // Directly to top right
                        ),
                        
                        // Bottom diagonal remains the same
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.25, y: height * 0.5), // Start from middle left
                            end: CGPoint(x: width * 0.4, y: height * 0.6)     // First segment of bottom diagonal
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.4, y: height * 0.6),  // Matches previous end
                            end: CGPoint(x: width * 0.55, y: height * 0.7)    // Second segment of bottom diagonal
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.55, y: height * 0.7), // Matches previous end
                            end: CGPoint(x: width * 0.7, y: height * 0.8)     // End at bottom right
                        )
                    ]
                }
            )
        case "L":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital L
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // 1. Top
                        CGPoint(x: width * 0.25, y: height * 0.5),  // 2. Middle
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 3. Bottom left
                        CGPoint(x: width * 0.7, y: height * 0.8)    // 4. Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Horizontal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.8),
                            end: CGPoint(x: width * 0.45, y: height * 0.8)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.45, y: height * 0.8),
                            end: CGPoint(x: width * 0.7, y: height * 0.8)
                        )
                    ]
                }
            )
        case "M":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital M
                    path.move(to: CGPoint(x: width * 0.2, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.2, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.2, y: height * 0.8),   // 1. Bottom left
                        CGPoint(x: width * 0.2, y: height * 0.2),   // 2. Top left
                        CGPoint(x: width * 0.5, y: height * 0.5),   // Middle peak
                        CGPoint(x: width * 0.8, y: height * 0.2),   // 4. Top right
                        CGPoint(x: width * 0.8, y: height * 0.8)    // Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left vertical
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.2, y: height * 0.8),
                            end: CGPoint(x: width * 0.2, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.2, y: height * 0.5),
                            end: CGPoint(x: width * 0.2, y: height * 0.2)
                        ),
                        
                        // First diagonal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.2, y: height * 0.2),
                            end: CGPoint(x: width * 0.35, y: height * 0.35)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.35, y: height * 0.35),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        
                        // Second diagonal
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.65, y: height * 0.35)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.65, y: height * 0.35),
                            end: CGPoint(x: width * 0.8, y: height * 0.2)
                        ),
                        
                        // Right vertical
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.8, y: height * 0.2),
                            end: CGPoint(x: width * 0.8, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.8, y: height * 0.5),
                            end: CGPoint(x: width * 0.8, y: height * 0.8)
                        )
                    ]
                }
            )
        case "N":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital N
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 1. Bottom left
                        CGPoint(x: width * 0.25, y: height * 0.2),  // 2. Top left
                        CGPoint(x: width * 0.5, y: height * 0.5),   // Middle diagonal
                        CGPoint(x: width * 0.75, y: height * 0.8),  // 4. Bottom right
                        CGPoint(x: width * 0.75, y: height * 0.2)   // 5. Top right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left vertical
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.8),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.2)
                        ),
                        
                        // Diagonal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.75, y: height * 0.8)
                        ),
                        
                        // Right vertical
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.75, y: height * 0.8),
                            end: CGPoint(x: width * 0.75, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.75, y: height * 0.5),
                            end: CGPoint(x: width * 0.75, y: height * 0.2)
                        )
                    ]
                }
            )
        case "O":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital O - full ellipse
                    path.addEllipse(in: CGRect(x: width * 0.25, y: height * 0.2,
                                               width: width * 0.5, height: height * 0.6))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.5, y: height * 0.2),   // 1. Top
                        CGPoint(x: width * 0.75, y: height * 0.35), // Top right
                        CGPoint(x: width * 0.75, y: height * 0.65), // 3. Bottom right
                        CGPoint(x: width * 0.5, y: height * 0.8),   // 4. Bottom
                        CGPoint(x: width * 0.25, y: height * 0.65), // 5. Bottom left
                        CGPoint(x: width * 0.25, y: height * 0.35)  // 6. Top left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Clockwise arrows around the oval with more segments
                        // Top right quadrant
                        // Top right quadrant
                        // Top right quadrant
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.58, y: height * 0.225) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.58, y: height * 0.225),
                            end: CGPoint(x: width * 0.67, y: height * 0.275) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.67, y: height * 0.275),
                            end: CGPoint(x: width * 0.75, y: height * 0.35)
                        ),
                        // Right side
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.75, y: height * 0.35),
                            end: CGPoint(x: width * 0.75, y: height * 0.5) // Changed from 0.77 to 0.75
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.75, y: height * 0.5), // Changed from 0.77 to 0.75
                            end: CGPoint(x: width * 0.75, y: height * 0.65)
                        ),
                        // Bottom right quadrant
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.75, y: height * 0.65),
                            end: CGPoint(x: width * 0.67, y: height * 0.725) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.67, y: height * 0.725),
                            end: CGPoint(x: width * 0.58, y: height * 0.775) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.58, y: height * 0.775),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        ),
                        // Bottom left quadrant
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.5, y: height * 0.8),
                            end: CGPoint(x: width * 0.42, y: height * 0.775) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.42, y: height * 0.775),
                            end: CGPoint(x: width * 0.33, y: height * 0.725) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.33, y: height * 0.725),
                            end: CGPoint(x: width * 0.25, y: height * 0.65)
                        ),
                        // Left side
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.25, y: height * 0.65),
                            end: CGPoint(x: width * 0.25, y: height * 0.5) // Changed from 0.23 to 0.25
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.25, y: height * 0.5), // Changed from 0.23 to 0.25
                            end: CGPoint(x: width * 0.25, y: height * 0.35)
                        ),
                        // Top left quadrant
                        ArrowPathData(
                            id: 14,
                            start: CGPoint(x: width * 0.25, y: height * 0.35),
                            end: CGPoint(x: width * 0.33, y: height * 0.275) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 15,
                            start: CGPoint(x: width * 0.33, y: height * 0.275),
                            end: CGPoint(x: width * 0.42, y: height * 0.225) // Adjusted to follow curve
                        ),
                        ArrowPathData(
                            id: 16,
                            start: CGPoint(x: width * 0.42, y: height * 0.225),
                            end: CGPoint(x: width * 0.5, y: height * 0.2)
                        )
                    ]
                }
            )
        case "P":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital P with curved loop
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    
                    // Top horizontal line
                    path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.2))
                    
                    // Modified curved part to match arrow path exactly
                    // Using multiple curves to match the segments more precisely
                    let curvePoints = [
                        CGPoint(x: width * 0.68, y: height * 0.23),
                        CGPoint(x: width * 0.73, y: height * 0.28),
                        CGPoint(x: width * 0.75, y: height * 0.35), // Rightmost point
                        CGPoint(x: width * 0.73, y: height * 0.42),
                        CGPoint(x: width * 0.68, y: height * 0.47),
                        CGPoint(x: width * 0.6, y: height * 0.5)
                    ]
                    
                    // Start with a curve to the first point
                    path.addQuadCurve(
                        to: curvePoints[0],
                        control: CGPoint(x: width * 0.65, y: height * 0.2)
                    )
                    
                    // Add lines through all the points to match the arrow path exactly
                    for point in curvePoints[1...] {
                        path.addLine(to: point)
                    }
                    
                    // Add the final horizontal line
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 1. Bottom
                        CGPoint(x: width * 0.25, y: height * 0.5),  // 2. Middle
                        CGPoint(x: width * 0.25, y: height * 0.2),  // 3. Top left
                        CGPoint(x: width * 0.6, y: height * 0.2),   // 4. Top right
                        CGPoint(x: width * 0.7, y: height * 0.35)   // 5. Curve point
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical line remains the same
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.8),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.2)
                        ),
                        
                        // Top horizontal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.6, y: height * 0.2)
                        ),
                        
                        // Curve with more segments
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.6, y: height * 0.2),
                            end: CGPoint(x: width * 0.68, y: height * 0.23)
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.68, y: height * 0.23),
                            end: CGPoint(x: width * 0.73, y: height * 0.28)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.73, y: height * 0.28),
                            end: CGPoint(x: width * 0.75, y: height * 0.35)
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.75, y: height * 0.35),
                            end: CGPoint(x: width * 0.73, y: height * 0.42)
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.73, y: height * 0.42),
                            end: CGPoint(x: width * 0.68, y: height * 0.47)
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.68, y: height * 0.47),
                            end: CGPoint(x: width * 0.6, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.6, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        )
                    ]
                }
            )
        case "Q":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital Q (O with a tail)
                    path.addEllipse(in: CGRect(x: width * 0.25, y: height * 0.2,
                                               width: width * 0.5, height: height * 0.6))
                    
                    path.move(to: CGPoint(x: width * 0.6, y: height * 0.65))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.5, y: height * 0.2),   // 1. Top
                        CGPoint(x: width * 0.75, y: height * 0.35), // Top right
                        CGPoint(x: width * 0.75, y: height * 0.65), // 3. Bottom right
                        CGPoint(x: width * 0.5, y: height * 0.8),   // 4. Bottom
                        CGPoint(x: width * 0.25, y: height * 0.65), // 5. Bottom left
                        CGPoint(x: width * 0.25, y: height * 0.35)  // 6. Top left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Top right quadrant - Adjusted for circular curve
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.58, y: height * 0.225)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.58, y: height * 0.225),
                            end: CGPoint(x: width * 0.67, y: height * 0.275)
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.67, y: height * 0.275),
                            end: CGPoint(x: width * 0.75, y: height * 0.35)
                        ),
                        // Right side - Aligned vertically
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.75, y: height * 0.35),
                            end: CGPoint(x: width * 0.75, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.75, y: height * 0.5),
                            end: CGPoint(x: width * 0.75, y: height * 0.65)
                        ),
                        // Bottom right quadrant - Adjusted for circular curve
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.75, y: height * 0.65),
                            end: CGPoint(x: width * 0.67, y: height * 0.725)
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.67, y: height * 0.725),
                            end: CGPoint(x: width * 0.58, y: height * 0.775)
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.58, y: height * 0.775),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        ),
                        // Bottom left quadrant - Adjusted for circular curve
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.5, y: height * 0.8),
                            end: CGPoint(x: width * 0.42, y: height * 0.775)
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.42, y: height * 0.775),
                            end: CGPoint(x: width * 0.33, y: height * 0.725)
                        ),
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.33, y: height * 0.725),
                            end: CGPoint(x: width * 0.25, y: height * 0.65)
                        ),
                        // Left side - Aligned vertically
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.25, y: height * 0.65),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.35)
                        ),
                        // Top left quadrant - Adjusted for circular curve
                        ArrowPathData(
                            id: 14,
                            start: CGPoint(x: width * 0.25, y: height * 0.35),
                            end: CGPoint(x: width * 0.33, y: height * 0.275)
                        ),
                        ArrowPathData(
                            id: 15,
                            start: CGPoint(x: width * 0.33, y: height * 0.275),
                            end: CGPoint(x: width * 0.42, y: height * 0.225)
                        ),
                        ArrowPathData(
                            id: 16,
                            start: CGPoint(x: width * 0.42, y: height * 0.225),
                            end: CGPoint(x: width * 0.5, y: height * 0.2)
                        ),
                        // Tail of Q
                        ArrowPathData(
                            id: 17,
                            start: CGPoint(x: width * 0.6, y: height * 0.65),
                            end: CGPoint(x: width * 0.68, y: height * 0.73)
                        ),
                        ArrowPathData(
                            id: 18,
                            start: CGPoint(x: width * 0.68, y: height * 0.73),
                            end: CGPoint(x: width * 0.75, y: height * 0.8)
                        )
                    ]
                }
            )
        case "R":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital R with loop and leg
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    
                    // Top horizontal line
                    path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.2))
                    
                    // Modified curved part to match arrow path exactly
                    // Using the same points defined in the arrow path
                    let curvePoints = [
                        CGPoint(x: width * 0.68, y: height * 0.23),
                        CGPoint(x: width * 0.73, y: height * 0.28),
                        CGPoint(x: width * 0.75, y: height * 0.35), // Rightmost point
                        CGPoint(x: width * 0.73, y: height * 0.42),
                        CGPoint(x: width * 0.68, y: height * 0.47),
                        CGPoint(x: width * 0.6, y: height * 0.5)
                    ]
                    
                    // Start with a small curve to the first point
                    path.addQuadCurve(
                        to: curvePoints[0],
                        control: CGPoint(x: width * 0.65, y: height * 0.2)
                    )
                    
                    // Add lines through all the points to match the arrow path exactly
                    for point in curvePoints[1...] {
                        path.addLine(to: point)
                    }
                    
                    // Add the final horizontal line
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    
                    // Diagonal leg (keeping this part the same)
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.8),  // 1. Bottom left
                        CGPoint(x: width * 0.25, y: height * 0.5),  // 2. Middle left
                        CGPoint(x: width * 0.25, y: height * 0.2),  // 3. Top left
                        CGPoint(x: width * 0.6, y: height * 0.2),   // 4. Top right
                        CGPoint(x: width * 0.7, y: height * 0.35),  // 5. Curve point
                        CGPoint(x: width * 0.7, y: height * 0.8)    // 6. Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Vertical line remains the same
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.8),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.2)
                        ),
                        
                        // Top horizontal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.6, y: height * 0.2)
                        ),
                        
                        // Curve with more segments
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.6, y: height * 0.2),
                            end: CGPoint(x: width * 0.68, y: height * 0.23)
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.68, y: height * 0.23),
                            end: CGPoint(x: width * 0.73, y: height * 0.28)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.73, y: height * 0.28),
                            end: CGPoint(x: width * 0.75, y: height * 0.35)
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.75, y: height * 0.35),
                            end: CGPoint(x: width * 0.73, y: height * 0.42)
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.73, y: height * 0.42),
                            end: CGPoint(x: width * 0.68, y: height * 0.47)
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.68, y: height * 0.47),
                            end: CGPoint(x: width * 0.6, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.6, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.5)
                        ),
                        // Diagonal leg - recalculated to follow a perfect straight line
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.25, y: height * 0.5),
                            end: CGPoint(x: width * 0.35, y: height * 0.567) // Adjusted to be on straight line
                        ),
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.35, y: height * 0.567),
                            end: CGPoint(x: width * 0.45, y: height * 0.633) // Adjusted to be on straight line
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.45, y: height * 0.633),
                            end: CGPoint(x: width * 0.55, y: height * 0.7) // Adjusted to be on straight line
                        ),
                        ArrowPathData(
                            id: 14,
                            start: CGPoint(x: width * 0.55, y: height * 0.7),
                            end: CGPoint(x: width * 0.7, y: height * 0.8)
                        )
                                    ]
                                }
                            )
        case "S":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital S with proper curves
                    path.move(to: CGPoint(x: width * 0.7, y: height * 0.25))
                    
                    // Top curve
                    path.addCurve(
                        to: CGPoint(x: width * 0.3, y: height * 0.4),
                        control1: CGPoint(x: width * 0.7, y: height * 0.15),
                        control2: CGPoint(x: width * 0.3, y: height * 0.2)
                    )
                    
                    // Middle S-curve
                    path.addCurve(
                        to: CGPoint(x: width * 0.7, y: height * 0.6),
                        control1: CGPoint(x: width * 0.3, y: height * 0.5),
                        control2: CGPoint(x: width * 0.7, y: height * 0.4)
                    )
                    
                    // Bottom curve
                    path.addCurve(
                        to: CGPoint(x: width * 0.3, y: height * 0.75),
                        control1: CGPoint(x: width * 0.7, y: height * 0.8),
                        control2: CGPoint(x: width * 0.3, y: height * 0.95)
                    )
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.7, y: height * 0.25),  // 1. Top right
                        CGPoint(x: width * 0.5, y: height * 0.2),   // 2. Top curve
                        CGPoint(x: width * 0.3, y: height * 0.4),   // 3. Top curve end
                        CGPoint(x: width * 0.5, y: height * 0.5),   // 4. Middle
                        CGPoint(x: width * 0.7, y: height * 0.6),   // 5. Bottom curve start
                        CGPoint(x: width * 0.5, y: height * 0.8),   // 6. Bottom curve
                        CGPoint(x: width * 0.3, y: height * 0.75)   // 7. Bottom left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Arrow 1 - Unchanged
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.7, y: height * 0.25),
                            end: CGPoint(x: width * 0.68, y: height * 0.23) // Reduced gradient
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.68, y: height * 0.23),
                            end: CGPoint(x: width * 0.6, y: height * 0.20) // Lowered
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.6, y: height * 0.20),
                            end: CGPoint(x: width * 0.45, y: height * 0.24)
                        ),
                        // Remaining arrows - Unchanged
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.45, y: height * 0.24),
                            end: CGPoint(x: width * 0.38, y: height * 0.28) // Lower gradient
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.38, y: height * 0.28),
                            end: CGPoint(x: width * 0.33, y: height * 0.32)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.33, y: height * 0.32),
                            end: CGPoint(x: width * 0.3, y: height * 0.4)
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.3, y: height * 0.4),
                            end: CGPoint(x: width * 0.35, y: height * 0.45)
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.35, y: height * 0.45),
                            end: CGPoint(x: width * 0.45, y: height * 0.46)
                        ),
                        ArrowPathData(
                            id: 9,
                            start: CGPoint(x: width * 0.45, y: height * 0.46),
                            end: CGPoint(x: width * 0.55, y: height * 0.48)
                        ),
                        ArrowPathData(
                            id: 10,
                            start: CGPoint(x: width * 0.55, y: height * 0.48),
                            end: CGPoint(x: width * 0.65, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 11,
                            start: CGPoint(x: width * 0.65, y: height * 0.5),
                            end: CGPoint(x: width * 0.7, y: height * 0.58)
                        ),
                        ArrowPathData(
                            id: 12,
                            start: CGPoint(x: width * 0.7, y: height * 0.58),
                            end: CGPoint(x: width * 0.68, y: height * 0.68)
                        ),
                        ArrowPathData(
                            id: 13,
                            start: CGPoint(x: width * 0.68, y: height * 0.68),
                            end: CGPoint(x: width * 0.62, y: height * 0.75)
                        ),
                        ArrowPathData(
                            id: 14,
                            start: CGPoint(x: width * 0.62, y: height * 0.75),
                            end: CGPoint(x: width * 0.55, y: height * 0.8)
                        ),
                        ArrowPathData(
                            id: 15,
                            start: CGPoint(x: width * 0.55, y: height * 0.8),
                            end: CGPoint(x: width * 0.45, y: height * 0.85)
                        ),
                        ArrowPathData(
                            id: 16,
                            start: CGPoint(x: width * 0.45, y: height * 0.85),
                            end: CGPoint(x: width * 0.38, y: height * 0.853)
                        ),
                        ArrowPathData(
                            id: 17,
                            start: CGPoint(x: width * 0.38, y: height * 0.853),
                            end: CGPoint(x: width * 0.32, y: height * 0.8)
                        ),
                        ArrowPathData(
                            id: 18,
                            start: CGPoint(x: width * 0.32, y: height * 0.8),
                            end: CGPoint(x: width * 0.287, y: height * 0.73)
                        )
                    ]
                }
            )
        case "T":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital T
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.5, y: height * 0.2),   // 2. Top center
                        CGPoint(x: width * 0.75, y: height * 0.2),  // 3. Top right
                        CGPoint(x: width * 0.5, y: height * 0.5),   // 4. Middle
                        CGPoint(x: width * 0.5, y: height * 0.8)    // 5. Bottom
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Horizontal
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.2)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.75, y: height * 0.2)
                        ),
                        
                        // Vertical
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        )
                    ]
                }
            )
        case "U":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
        // Capital U
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.6))
                    path.addCurve(
                        to: CGPoint(x: width * 0.75, y: height * 0.6),
                        control1: CGPoint(x: width * 0.25, y: height * 0.8),
                        control2: CGPoint(x: width * 0.75, y: height * 0.8)
                    )
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2), // Top left
                        CGPoint(x: width * 0.25, y: height * 0.6), // 2. Middle left
                        CGPoint(x: width * 0.5, y: height * 0.8), // 3. Bottom curve
                        CGPoint(x: width * 0.75, y: height * 0.6), // 4. Middle right
                        CGPoint(x: width * 0.75, y: height * 0.2) // 5. Top right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left vertical
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.25, y: height * 0.6)
                        ),
                        // Bottom curve with higher segments
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.25, y: height * 0.6),
                            end: CGPoint(x: width * 0.3, y: height * 0.7)
                        ),
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.3, y: height * 0.7),
                            end: CGPoint(x: width * 0.4, y: height * 0.75)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.4, y: height * 0.75),
                            end: CGPoint(x: width * 0.5, y: height * 0.76) // Raised curve
                        ),
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.5, y: height * 0.76),
                            end: CGPoint(x: width * 0.6, y: height * 0.75)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.6, y: height * 0.75),
                            end: CGPoint(x: width * 0.7, y: height * 0.7)
                        ),
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.7, y: height * 0.7),
                            end: CGPoint(x: width * 0.75, y: height * 0.6)
                        ),
                        // Right vertical
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.75, y: height * 0.6),
                            end: CGPoint(x: width * 0.75, y: height * 0.2)
                        )
                    ]
                }
        )
        case "V":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital V - Straight lines
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2)) // Top left
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.8)) // Bottom point
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.2)) // Top right
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.5, y: height * 0.8),   // 2. Bottom point
                        CGPoint(x: width * 0.75, y: height * 0.2)   // 3. Top right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left diagonal - Single straight line
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2), // Top left
                            end: CGPoint(x: width * 0.5, y: height * 0.8)    // Bottom point
                        ),
                        
                        // Right diagonal - Single straight line
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.5, y: height * 0.8),  // Bottom point
                            end: CGPoint(x: width * 0.75, y: height * 0.2)    // Top right
                        )
                    ]
                }
            )
        case "W":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital W
                    path.move(to: CGPoint(x: width * 0.2, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.35, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.4))
                    path.addLine(to: CGPoint(x: width * 0.65, y: height * 0.8))
                    path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.2))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.2, y: height * 0.2),   // Top left
                        CGPoint(x: width * 0.35, y: height * 0.8),  // 2. First bottom
                        CGPoint(x: width * 0.5, y: height * 0.4),   // Middle peak
                        CGPoint(x: width * 0.65, y: height * 0.8),  // 4. Second bottom
                        CGPoint(x: width * 0.8, y: height * 0.2)    // 5. Top right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // First diagonal
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.2, y: height * 0.2),
                            end: CGPoint(x: width * 0.275, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.275, y: height * 0.5),
                            end: CGPoint(x: width * 0.35, y: height * 0.8)
                        ),
                        
                        // Second diagonal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.35, y: height * 0.8),
                            end: CGPoint(x: width * 0.425, y: height * 0.6)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.425, y: height * 0.6),
                            end: CGPoint(x: width * 0.5, y: height * 0.4)
                        ),
                        
                        // Third diagonal
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.5, y: height * 0.4),
                            end: CGPoint(x: width * 0.575, y: height * 0.6)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.575, y: height * 0.6),
                            end: CGPoint(x: width * 0.65, y: height * 0.8)
                        ),
                        
                        // Fourth diagonal
                        ArrowPathData(
                            id: 7,
                            start: CGPoint(x: width * 0.65, y: height * 0.8),
                            end: CGPoint(x: width * 0.725, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 8,
                            start: CGPoint(x: width * 0.725, y: height * 0.5),
                            end: CGPoint(x: width * 0.8, y: height * 0.2)
                        )
                    ]
                }
            )
        case "X":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital X
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.8))
                    
                    path.move(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.5, y: height * 0.5),   // 2. Center
                        CGPoint(x: width * 0.75, y: height * 0.8),  // 3. Bottom right
                        CGPoint(x: width * 0.75, y: height * 0.2),  // 4. Top right
                        CGPoint(x: width * 0.25, y: height * 0.8)   // 5. Bottom left
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // First diagonal
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.75, y: height * 0.8)
                        ),
                        
                        // Second diagonal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.75, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        )
                    ]
                }
            )
        case "Y":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Capital Y
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    
                    path.move(to: CGPoint(x: width * 0.5, y: height * 0.5))
                    path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                        CGPoint(x: width * 0.5, y: height * 0.5),   // 2. Center
                        CGPoint(x: width * 0.75, y: height * 0.2),  // 3. Top right
                        CGPoint(x: width * 0.5, y: height * 0.8)    // 4. Bottom
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Left diagonal
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        
                        // Right diagonal
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.75, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        
                        // Vertical
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        )
                    ]
                }
            )
        case "Z":
            return TracingPathDefinition(
                path: { rect in
                    let width = rect.width
                    let height = rect.height
                    var path = Path()
                    
                    // Top horizontal
                    path.move(to: CGPoint(x: width * 0.25, y: height * 0.2))
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.2))
                    
                    // Diagonal
                    path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.8))
                    
                    // Bottom horizontal
                    path.addLine(to: CGPoint(x: width * 0.75, y: height * 0.8))
                    
                    return path
                },
                guidePoints: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        CGPoint(x: width * 0.25, y: height * 0.2), // Top left
                        CGPoint(x: width * 0.75, y: height * 0.2), // Top right
                        CGPoint(x: width * 0.5, y: height * 0.5),  // Middle
                        CGPoint(x: width * 0.25, y: height * 0.8), // Bottom left
                        CGPoint(x: width * 0.75, y: height * 0.8)  // Bottom right
                    ]
                },
                arrowPaths: { size in
                    let width = size.width
                    let height = size.height
                    return [
                        // Top horizontal
                        ArrowPathData(
                            id: 1,
                            start: CGPoint(x: width * 0.25, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.2)
                        ),
                        ArrowPathData(
                            id: 2,
                            start: CGPoint(x: width * 0.5, y: height * 0.2),
                            end: CGPoint(x: width * 0.75, y: height * 0.2)
                        ),
                        
                        // Diagonal
                        ArrowPathData(
                            id: 3,
                            start: CGPoint(x: width * 0.75, y: height * 0.2),
                            end: CGPoint(x: width * 0.5, y: height * 0.5)
                        ),
                        ArrowPathData(
                            id: 4,
                            start: CGPoint(x: width * 0.5, y: height * 0.5),
                            end: CGPoint(x: width * 0.25, y: height * 0.8)
                        ),
                        
                        // Bottom horizontal
                        ArrowPathData(
                            id: 5,
                            start: CGPoint(x: width * 0.25, y: height * 0.8),
                            end: CGPoint(x: width * 0.5, y: height * 0.8)
                        ),
                        ArrowPathData(
                            id: 6,
                            start: CGPoint(x: width * 0.5, y: height * 0.8),
                            end: CGPoint(x: width * 0.75, y: height * 0.8)
                        )
                    ]
                }
            )
            
            
            
        default:
            // default simple path if letter not implemented
            return createDefaultLetterPath()
        }
    }
    
    // Creates a default letter path for any unimplemented letter
    // just in case
    // reference point
    private static func createDefaultLetterPath() -> TracingPathDefinition {
        return TracingPathDefinition(
            path: { rect in
                let width = rect.width
                let height = rect.height
                var path = Path()
                
                path.move(to: CGPoint(x: width * 0.3, y: height * 0.3))
                path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.3))
                path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.7))
                path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.7))
                path.addLine(to: CGPoint(x: width * 0.3, y: height * 0.3))
                
                return path
            },
            guidePoints: { size in
                let width = size.width
                let height = size.height
                return [
                    CGPoint(x: width * 0.3, y: height * 0.3),
                    CGPoint(x: width * 0.7, y: height * 0.3),
                    CGPoint(x: width * 0.7, y: height * 0.7),
                    CGPoint(x: width * 0.3, y: height * 0.7)
                ]
            },
            arrowPaths: { size in
                let width = size.width
                let height = size.height
                return [
                    ArrowPathData(id: 1, start: CGPoint(x: width * 0.3, y: height * 0.3), end: CGPoint(x: width * 0.7, y: height * 0.3)),
                    ArrowPathData(id: 2, start: CGPoint(x: width * 0.7, y: height * 0.3), end: CGPoint(x: width * 0.7, y: height * 0.7)),
                    ArrowPathData(id: 3, start: CGPoint(x: width * 0.7, y: height * 0.7), end: CGPoint(x: width * 0.3, y: height * 0.7)),
                    ArrowPathData(id: 4, start: CGPoint(x: width * 0.3, y: height * 0.7), end: CGPoint(x: width * 0.3, y: height * 0.3))
                ]
            }
        )
    }
}

// pen lifts version
struct EnhancedLetterPathFactory {
    // Get enhanced letter path definition for letters that need pen lifting
    static func getEnhancedLetterPath(for letter: String) -> EnhancedTracingPathDefinition? {
        // Only return enhanced definitions for letters that need pen lifts
        switch letter {
            // decided which letters would need pen lifts
        case "A":
            return createEnhancedA()
        case "E":
            return createEnhancedE()
        case "F":
            return createEnhancedF()
        case "H":
            return createEnhancedH()
        case "I":
            return createEnhancedI()
        case "J":
            return createEnhancedJ()
        case "K":
            return createEnhancedK()
        case "Q":
            return createEnhancedQ()
        case "T":
            return createEnhancedT()
        case "X":
            return createEnhancedX()
        case "Y":
            return createEnhancedY()
        default:
            return nil
        }
    }
    
    // Check if a letter needs pen lifting
    static func letterNeedsPenLifting(_ letter: String) -> Bool {
        return ["A", "E", "F", "H", "I", "J", "K", "Q", "T", "X", "Y"].contains(letter)
    }
    
    // definitons if pen lift
    private static func createEnhancedA() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "A")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // left diagonal, right diagonal + the horizontal bar segments
                return [
                    // First segment: left diagonal stroke
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.2, y: height * 0.8),  // Bottom left
                            CGPoint(x: width * 0.35, y: height * 0.5), // Middle point
                            CGPoint(x: width * 0.5, y: height * 0.2)   // Top middle
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: right diagonal stroke
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.5, y: height * 0.2),  // Top middle
                            CGPoint(x: width * 0.65, y: height * 0.5), // Middle point
                            CGPoint(x: width * 0.8, y: height * 0.8)   // Bottom right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: horizontal line (middle)
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.35, y: height * 0.5), // Left middle
                            CGPoint(x: width * 0.65, y: height * 0.5)  // Right middle
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedE() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "E")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Four segments: vertical line, top horizontal, middle horizontal, bottom horizontal
                return [
                    // First segment: vertical line
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle
                            CGPoint(x: width * 0.25, y: height * 0.8)   // Bottom
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: top horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.7, y: height * 0.2)    // Top right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: middle horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                            CGPoint(x: width * 0.6, y: height * 0.5)    // Middle right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Fourth segment: bottom horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.8),  // Bottom left
                            CGPoint(x: width * 0.7, y: height * 0.8)    // Bottom right
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedF() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "F")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Three segments: vertical line, top horizontal, middle horizontal
                return [
                    // First segment: vertical line
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle
                            CGPoint(x: width * 0.25, y: height * 0.8)   // Bottom
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: top horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.7, y: height * 0.2)    // Top right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: middle horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                            CGPoint(x: width * 0.6, y: height * 0.5)    // Middle right
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedH() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "H")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Three segments: left vertical, right vertical, middle horizontal
                return [
                    // First segment: left vertical
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                            CGPoint(x: width * 0.25, y: height * 0.8)   // Bottom left
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: right vertical
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.75, y: height * 0.2),  // Top right
                            CGPoint(x: width * 0.75, y: height * 0.5),  // Middle right
                            CGPoint(x: width * 0.75, y: height * 0.8)   // Bottom right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: middle horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                            CGPoint(x: width * 0.75, y: height * 0.5)   // Middle right
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedI() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "I")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Three segments: top horizontal, vertical, bottom horizontal
                return [
                    // First segment: top horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.35, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.65, y: height * 0.2)   // Top right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: vertical
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.5, y: height * 0.2),   // Top
                            CGPoint(x: width * 0.5, y: height * 0.5),   // Middle
                            CGPoint(x: width * 0.5, y: height * 0.8)    // Bottom
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: bottom horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.35, y: height * 0.8),  // Bottom left
                            CGPoint(x: width * 0.65, y: height * 0.8)   // Bottom right
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedJ() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "J")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Two segments: top horizontal, J curve
                return [
                    // First segment: top horizontal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.5, y: height * 0.2),   // Top left
                            CGPoint(x: width * 0.8, y: height * 0.2)    // Top right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: J vertical and curve
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.65, y: height * 0.2),  // Top center
                            CGPoint(x: width * 0.65, y: height * 0.6),  // Middle right
                            CGPoint(x: width * 0.6, y: height * 0.75),  // Bottom curve
                            CGPoint(x: width * 0.5, y: height * 0.78),  // Bottom middle
                            CGPoint(x: width * 0.4, y: height * 0.75),  // Bottom curve
                            CGPoint(x: width * 0.35, y: height * 0.6)   // Bottom left
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedK() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "K")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Three segments: vertical line, top diagonal, bottom diagonal
                return [
                    // First segment: vertical line
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle
                            CGPoint(x: width * 0.25, y: height * 0.8)   // Bottom
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: top diagonal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                            CGPoint(x: width * 0.7, y: height * 0.2)    // Top right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: bottom diagonal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Middle left
                            CGPoint(x: width * 0.7, y: height * 0.8)    // Bottom right
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedQ() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "Q")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Two segments: circle, diagonal tail
                return [
                    // First segment: circle
                    PathSegment(
                        points: [
                            // Start from top and go clockwise
                            CGPoint(x: width * 0.5, y: height * 0.2),   // Top
                            CGPoint(x: width * 0.65, y: height * 0.25), // Top right
                            CGPoint(x: width * 0.75, y: height * 0.35), // Right top
                            CGPoint(x: width * 0.75, y: height * 0.5),  // Right
                            CGPoint(x: width * 0.75, y: height * 0.65), // Right bottom
                            CGPoint(x: width * 0.65, y: height * 0.75), // Bottom right
                            CGPoint(x: width * 0.5, y: height * 0.8),   // Bottom
                            CGPoint(x: width * 0.35, y: height * 0.75), // Bottom left
                            CGPoint(x: width * 0.25, y: height * 0.65), // Left bottom
                            CGPoint(x: width * 0.25, y: height * 0.5),  // Left
                            CGPoint(x: width * 0.25, y: height * 0.35), // Left top
                            CGPoint(x: width * 0.35, y: height * 0.25), // Top left
                            CGPoint(x: width * 0.5, y: height * 0.2)    // Back to top to close
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: diagonal tail
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.6, y: height * 0.65),  // Start
                            CGPoint(x: width * 0.75, y: height * 0.8)   // End
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedT() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "T")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Two segments: horizontal, vertical
                return [
                    // First segment: horizontal line
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.75, y: height * 0.2)   // Top right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: vertical line
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.5, y: height * 0.2),   // Top center
                            CGPoint(x: width * 0.5, y: height * 0.5),   // Middle
                            CGPoint(x: width * 0.5, y: height * 0.8)    // Bottom
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedX() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "X")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Two segments: first diagonal, second diagonal
                return [
                    // First segment: top-left to bottom-right diagonal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.5, y: height * 0.5),   // Middle
                            CGPoint(x: width * 0.75, y: height * 0.8)   // Bottom right
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: top-right to bottom-left diagonal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.75, y: height * 0.2),  // Top right
                            CGPoint(x: width * 0.5, y: height * 0.5),   // Middle
                            CGPoint(x: width * 0.25, y: height * 0.8)   // Bottom left
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
    
    private static func createEnhancedY() -> EnhancedTracingPathDefinition {
        let originalPathDef = LetterPathFactory.letterPathDefinition(for: "Y")
        
        return EnhancedTracingPathDefinition(
            path: originalPathDef.path,
            guidePoints: originalPathDef.guidePoints,
            arrowPaths: originalPathDef.arrowPaths,
            strokeSegments: { size in
                let width = size.width
                let height = size.height
                
                // Three segments: left diagonal, right diagonal, and vertical
                return [
                    // First segment: top-left to middle diagonal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.25, y: height * 0.2),  // Top left
                            CGPoint(x: width * 0.5, y: height * 0.5)    // Middle
                        ],
                        isNewStroke: true
                    ),
                    
                    // Second segment: top-right to middle diagonal
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.75, y: height * 0.2),  // Top right
                            CGPoint(x: width * 0.5, y: height * 0.5)    // Middle
                        ],
                        isNewStroke: true
                    ),
                    
                    // Third segment: middle to bottom vertical
                    PathSegment(
                        points: [
                            CGPoint(x: width * 0.5, y: height * 0.5),   // Middle
                            CGPoint(x: width * 0.5, y: height * 0.8)    // Bottom
                        ],
                        isNewStroke: true
                    )
                ]
            }
        )
    }
}

// visual feedback components for better stimulation
// inspired by gizmooo (same feature but now on my app)
// code partially borrowed (reference)
struct ConfettiView: View {
    @State private var isVisible = false
    var count: Int = 20
    @State private var isAnimating = false // Add this binding
    
    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                ConfettiPiece(
                    Color: self.randomColor(),
                    shape: i % 3 == 0 ? .circle : (i % 3 == 1 ? .triangle : .rectangle),
                    // triangle defined later
                    position: self.randomPosition(),
                    angle: Double.random(in: 0...360),
                    isAnimating: $isAnimating
                )
                .opacity(isVisible ? 1 : 0)
            }
        }
        .onAppear {
            isAnimating = true
            withAnimation(Animation.easeOut(duration: 0.5)) {
                isVisible = true
            }
        }
    }
    
    private func randomColor() -> Color {
        let Colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
        return Colors.randomElement()!
    }
    
    private func randomRotation() -> Double {
        return Double.random(in: 0..<360)
    }
    
    private func randomPosition() -> CGPoint {
        return CGPoint(x: CGFloat.random(in: -150...150), y: CGFloat.random(in: -200...0))
    }
}

struct PhysicsConfettiView: View {
    var count: Int = 50
    var Colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                ConfettiPiece(
                    Color: Colors.randomElement() ?? .blue,
                    shape: i % 3 == 0 ? .circle : (i % 3 == 1 ? .triangle : .rectangle),
                    position: randomPosition(),
                    angle: Double.random(in: 0...360),
                    isAnimating: $isAnimating
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAnimating = true
            }
        }
    }
    
    private func randomPosition() -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: -50...50),
            y: CGFloat.random(in: -20...20)
        )
    }
}
struct ConfettiPiece: View {
    let Color: Color
    var shape: ConfettiShape = .circle
    var position: CGPoint = .zero
    var angle: Double = 0
    @Binding var isAnimating: Bool
    
    enum ConfettiShape {
        case circle, triangle, rectangle
    }
    
    var body: some View {
        Group {
            switch shape {
            case .circle:
                Circle().fill(Color)
            case .triangle:
                Triangle().fill(Color)
            case .rectangle:
                Rectangle().fill(Color)
            }
        }
        .frame(width: 8, height: 8)
        .rotationEffect(Angle.degrees(angle))
        .position(position)
        .opacity(isAnimating ? 1 : 0)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}


struct AnimatedCharacterBubble: View {
    let emoji: String
    let message: String

    @State private var appear = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.system(size: 48))

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.body)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white).shadow(radius: 2))
            }
        }
        .padding()
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appear = true
            }
        }
        .scaleEffect(appear ? 1 : 0.8)
        .opacity(appear ? 1 : 0)
    }
}


struct FocusCardView: View {
    let letter: String
    let score: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(letter)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.primary)

                Text(score != nil ? "Avg: \(String(format: "%.0f", score!))%" : "No Data")
                    .font(.subheadline)
                    .foregroundColor(scoreColor(score))
            }
            .frame(width: 80, height: 100)
            .background(AppTheme.cardBackground)
            .cornerRadius(16)
            .shadow(radius: 4)
        }
    }

    private func scoreColor(_ score: Double?) -> Color {
        guard let s = score else { return .gray }
        return s >= 80 ? .green : (s >= 50 ? .orange : .red)
    }
}

struct ConfettiEmitter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let emitter = CAEmitterLayer()

        emitter.emitterPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: -10)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: UIScreen.main.bounds.width, height: 1)

        let cell = CAEmitterCell()
        cell.birthRate = 4
        cell.lifetime = 6.0
        cell.velocity = 150
        cell.velocityRange = 100
        cell.emissionLongitude = .pi
        cell.spin = 4
        cell.spinRange = 2
        cell.scale = 0.3
        cell.scaleRange = 0.2
        cell.Color = UIColor.systemPink.cgColor
        cell.contents = UIImage(systemName: "star.fill")?.withTintColor(.systemPink, renderingMode: .alwaysOriginal).cgImage

        emitter.emitterCells = [cell]
        view.layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            emitter.birthRate = 0
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct EnhancedCelebrationView: View {
    let message: String
    let score: Double
    let letter: String
    let onDismiss: () -> Void
    @State private var scale: CGFloat = 0.8
    @State private var rotation: Double = -5
    @State private var starScale: CGFloat = 0.1
    @State private var starOpacity: Double = 0
    @State private var confettiCount = 50
    let characterEmoji: String
    
    var body: some View {
        ZStack {
            // Background dim
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture(perform: onDismiss)
            
            // Celebration card
            VStack(spacing: 10) {
                // Animated letter with stars
                ZStack {
                    // Background shape
                    Circle()
                        .fill(AppTheme.secondaryColor.opacity(0.2))
                        .frame(width: 120, height: 120)
                    
                    // Letter
                    Text(letter)
                        .font(AppTheme.roundedFont(size: 70, weight: .bold))
                        .foregroundColor(AppTheme.primaryColor)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                rotation = 5
                            }
                        }
                    
                    // Animated stars
                    ForEach(0..<5) { i in
                        Image(systemName: "star.fill")
                            .foregroundColor(AppTheme.secondaryColor)
                            .offset(
                                x: CGFloat.random(in: -60...60),
                                y: CGFloat.random(in: -60...60)
                            )
                            .scaleEffect(starScale)
                            .opacity(starOpacity)
                            .onAppear {
                                withAnimation(Animation.easeOut(duration: Double.random(in: 0.5...1.5)).delay(Double(i) * 0.1)) {
                                    starScale = CGFloat.random(in: 0.5...0.8)
                                    starOpacity = 1
                                }
                            }
                    }
                }
                .padding(.top, 20)
                
                // Confetti animation
                ConfettiView(count: confettiCount)
                    .frame(height: 50)
                
                // Character and message
                HStack(spacing: 15) {
                    Text(characterEmoji)
                        .font(.system(size: 40))
                        .scaleEffect(scale)
                        .onAppear {
                            withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                scale = 1.2
                            }
                        }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text(message)
                            .font(AppTheme.roundedFont(size: 22, weight: .bold))
                            .foregroundColor(AppTheme.successColor)
                            .multilineTextAlignment(.center)
                        
                        HStack {
                            Text("Score:")
                                .font(AppTheme.roundedFont(size: 18))
                                .foregroundColor(.primary.opacity(0.7))
                            
                            Text("\(Int(score))%")
                                .font(AppTheme.roundedFont(size: 22, weight: .bold))
                                .foregroundColor(progressColor(score))
                        }
                    }
                }
                .padding()
                
                // Earned rewards section
                if score >= 80 {
                    VStack(spacing: 10) {
                        Text("You earned:")
                            .font(AppTheme.roundedFont(size: 18))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 15) {
                            ForEach(getEarnedRewards(for: score), id: \.self) { reward in
                                Text(reward)
                                    .font(.system(size: 30))
                                    .scaleEffect(starScale)
                                    .opacity(starOpacity)
                                    .onAppear {
                                        withAnimation(Animation.spring().delay(0.5)) {
                                            starScale = 1.0
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
                
                // Continue button
                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                        Text("Continue")
                            .font(AppTheme.roundedFont(size: 20, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 200)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(AppTheme.primaryColor)
                            .shadow(color: AppTheme.primaryColor.opacity(0.5), radius: 5, x: 0, y: 3)
                    )
                }
                .padding(.vertical, 10)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.white)
                    .shadow(radius: 20)
            )
            .frame(width: 320)
            .scaleEffect(scale)
            .opacity(scale)
            .onAppear {
                // Initial appearance animation
                SoundManager.shared.playCelebration()
                withAnimation(Animation.spring()) {
                    scale = 1.0
                }
            }
        }
    }
    
    // rewards determined based on certain scores
    private func getEarnedRewards(for score: Double) -> [String] {
        var rewards: [String] = []
        
        // basic reward for completion
        rewards.append("⭐️")
        
        // Additional rewards based on score tiers
        if score >= 85 {
            rewards.append("🏆")
        }
        
        if score >= 90 {
            rewards.append("🎨")
        }
        
        if score >= 95 {
            rewards.append("🌟")
        }
        
        //  random extra reward for fun
        if Bool.random() && score >= 85 {
            let extraRewards = ["🎯", "🖌️", "✏️", "🎊"]
            if let extra = extraRewards.randomElement() {
                rewards.append(extra)
            }
        }
        
        return rewards
    }
}


// helper toggle button with icon
struct HelpToggleButton: View {
    var iconName: String
    var title: String
    @Binding var isOn: Bool
    var Color: Color
    var disabled: Bool = false
    
    var body: some View {
        Button(action: {
            if !disabled {
                SoundManager.shared.playClick()
                isOn.toggle()
            }
        }) {
            VStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 22))
                    .foregroundColor(isOn ? Color : .gray)
                
                Text(title)
                    .font(AppTheme.roundedFont(size: 12))
                    .foregroundColor(isOn ? Color : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? Color.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? Color : Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
            .opacity(disabled ? 0.5 : 1.0)
        }
        .disabled(disabled)
    }
}

// action button
struct ActionButton: View {
    var title: String
    var icon: String
    var Color: Color
    var action: () -> Void
    var disabled: Bool = false
    
    var body: some View {
        Button(action: {
            if !disabled {
                SoundManager.shared.playClick()
                action()
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(title)
                    .font(AppTheme.roundedFont(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(disabled ? Color.gray.opacity(0.3) : Color)
                    .shadow(color: disabled ? Color.clear : Color.opacity(0.5), radius: 5, x: 0, y: 2)
            )
        }
        .disabled(disabled)
    }
}

// pulsing button so its easier to see + more fun
struct PulsingButton: View {
    let icon: String
    let title: String
    let Color: Color
    let action: () -> Void
    @State private var pulsate = false
    
    var body: some View {
        Button(action: {
            SoundManager.shared.playClick()
            action()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                
                Text(title)
                    .font(AppTheme.roundedFont(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color)
                    
                    // Pulsing overlay
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color, lineWidth: 3)
                        .scaleEffect(pulsate ? 1.2 : 1)
                        .opacity(pulsate ? 0 : 0.4)
                }
            )
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulsate = true
            }
        }
    }
}

struct InstructionItem: View {
    var icon: String
    var title: String
    var description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(AppTheme.primaryColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppTheme.roundedFont(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.primaryColor)
                
                Text(description)
                    .font(AppTheme.roundedFont(size: 16))
                    .foregroundColor(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
    }
}

struct LetterProgressIndicator: View {
    var currentIndex: Int
    var totalCount: Int
    var letter: String
    var letterPerformances: [LetterPerformance]  //  to access letter scores
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VStack(spacing: 10) {
            // Current letter display
            Text(letter)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.primaryColor)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(AppTheme.primaryColor.opacity(0.15))
                )
                .overlay(
                    Circle()
                        .stroke(AppTheme.primaryColor, lineWidth: 2)
                        .opacity(0.5)
                )
                
            // Progress bar with Color coding
            HStack(spacing: 2) {
                ForEach(0..<totalCount, id: \.self) { index in
                    Capsule()
                        .fill(getColorForLetter(at: index))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            
            // Progress text
            Text("Letter \(currentIndex + 1) of \(totalCount)")
                .font(AppTheme.roundedFont(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }
    
    // Colour based on performance ((and or current position))
    private func getColorForLetter(at index: Int) -> Color {
        if index > currentIndex {
            // Future letters are gray
            return Color.gray.opacity(0.3)
        } else if index == currentIndex {
            // Current letter is what i set primary Color as
            return AppTheme.primaryColor
        } else {
            // past letters Colored by performance
            let letterAtIndex = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")[index % 26]
            let letterStr = String(letterAtIndex)
            
            // Find performance for this letter
            if let letterPerf = letterPerformances.first(where: { $0.letter == letterStr }) {
                return progressColor(letterPerf.averageScore)
            }
            
            // Default if no performance data
            return Color.gray.opacity(0.6)
        }
    }
}

// Colourful progress circle for kids
struct ChildFriendlyProgressCircle: View {
    var progress: Double // 0-100
    @State private var animateRotation = false
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(lineWidth: 12)
                .opacity(0.3)
                .foregroundColor(Color.gray)
            
            // Progress circle
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress/100, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                .foregroundColor(progressColor(progress))
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.spring(), value: progress)
            
            // Center content
            VStack(spacing: 0) {
                Text("\(Int(progress))")
                    .font(AppTheme.roundedFont(size: 22, weight: .bold))
                    .foregroundColor(progressColor(progress))
                
                Text("%")
                    .font(AppTheme.roundedFont(size: 14))
                    .foregroundColor(progressColor(progress))
            }
            
            // Fun decorative dots along the circle
            ForEach(0..<12) { i in
                if progress/100 * 12 >= Double(i) {
                    Circle()
                        .fill(progressColor(progress))
                        .frame(width: 6, height: 6)
                        .offset(x: 0, y: -32)
                        .rotationEffect(Angle(degrees: Double(i) * 30))
                }
            }
        }
        .rotationEffect(Angle(degrees: animateRotation ? 360 : 0))
        .onAppear {
            withAnimation(Animation.linear(duration: 30).repeatForever(autoreverses: false)) {
                animateRotation = progress > 85
            }
        }
    }
}

// Graph for progress history
struct ProgressHistoryGraph: View {
    let scores: [Double]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background grid
                VStack(spacing: 0) {
                    ForEach(0..<4) { i in
                        Divider()
                            .background(Color.gray.opacity(0.3))
                            .offset(y: geo.size.height / 4 * CGFloat(i))
                    }
                }
                
                // Score line
                Path { path in
                    let width = geo.size.width
                    let height = geo.size.height
                    let horizontalStep = width / CGFloat(max(1, scores.count - 1))
                    
                    for (index, score) in scores.enumerated() {
                        let x = horizontalStep * CGFloat(index)
                        let y = height - (height * CGFloat(score) / 100)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(AppTheme.primaryColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                
                // Score points
                ForEach(0..<scores.count, id: \.self) { index in
                    let score = scores[index]
                    let width = geo.size.width
                    let height = geo.size.height
                    let horizontalStep = width / CGFloat(max(1, scores.count - 1))
                    let x = horizontalStep * CGFloat(index)
                    let y = height - (height * CGFloat(score) / 100)
                    
                    Circle()
                        .fill(progressColor(score))
                        .frame(width: 10, height: 10)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

// Helper view for stats
struct StatView: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Progress circle view
struct ProgressCircle: View {
    var progress: Double // 0-100
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 10)
                .opacity(0.3)
                .foregroundColor(.gray)
            
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress/100, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                .foregroundColor(ColorForProgress(progress))
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
            
            Text("\(Int(progress))%")
                .font(.system(size: 20, weight: .bold))
        }
    }
    
    func ColorForProgress(_ value: Double) -> Color {
        if value >= 80 { return .green }
        else if value >= 60 { return .orange }
        else { return .red }
    }
}
// view upon login
struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var username = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var loginError = false
    @State private var isAnimating = false

    // displays all the different characters in rotating cycle
    let characters = ["🦊", "🐼", "🐰", "🐶", "🐱"]
    @State private var selectedCharacter = 0

    //allows different choices that are finally defined below
    enum ThemeOption: String, CaseIterable {
        case space = "Space"
        case forest = "Forest"
        case ocean = "Ocean"
        case mountain = "Mountain"
    }

    @State private var theme: ThemeOption = .space

    private var themeBackground: some View {
        switch theme {
        case .space:
            return AnyView(
                ZStack {
                    Color.black
                    Image(systemName: "star.fill")
                        .font(.system(size: 200))
                        .foregroundColor(Color.purple.opacity(0.3))
                }
            )
            
        case .forest:
            return AnyView(
                ZStack {
                    LinearGradient(
                        colors: [Color.green.opacity(0.7), Color.fromHex("#9BE564")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 180))
                        .foregroundColor(Color.green.opacity(0.3))
                        .offset(x: -100, y: -80)
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 120))
                        .foregroundColor(Color.green.opacity(0.25))
                        .offset(x: 90, y: 100)
                }
            )
            
        case .ocean:
            return AnyView(
                ZStack {
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.6), Color.fromHex("#89CFF0")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "drop.fill")
                        .font(.system(size: 180))
                        .foregroundColor(Color.blue.opacity(0.3))
                        .rotationEffect(.degrees(20))
                    Image(systemName: "fish.fill")
                        .font(.system(size: 100))
                        .foregroundColor(Color.teal.opacity(0.3))
                        .offset(x: 60, y: 80)
                }
            )
            
        case .mountain:
            return AnyView(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.fromHex("#D9EAF2"), // soft sky blue
                            Color.fromHex("#D8C4F2")  // pastel lavender
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 200))
                        .foregroundColor(Color.white.opacity(0.2))
                        .offset(x: 0, y: 80)
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 140))
                        .foregroundColor(Color.yellow.opacity(0.3))
                        .offset(x: -80, y: -100)
                }
            )
        }
    }


    var preferences: UserPreferences {
        authManager.currentUser?.preferences ?? UserPreferences()
    }

    var body: some View {
        NavigationView {
            ZStack {
                themeBackground
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 25) {
                    Text("Letter Friends")
                        .font(AppTheme.roundedFont(size: 40, weight: .bold))
                        .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
                        .padding(.top, 40)

                    Text("Tracing Fun!")
                        .font(AppTheme.roundedFont(size: 28, weight: .medium))
                        .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences).opacity(0.8))

                    VStack(spacing: 10) {
                        ZStack {
                            ForEach(0..<characters.count, id: \.self) { index in
                                AnimatedCharacter(
                                    character: characters[index],
                                    isAnimating: isAnimating && index == selectedCharacter
                                )
                                .opacity(index == selectedCharacter ? 1 : 0)
                                .offset(x: 0, y: index == selectedCharacter ? -10 : 0)
                            }
                        }
                        .frame(height: 100)

                        HStack(spacing: 12) {
                            ForEach(ThemeOption.allCases, id: \.self) { theme in
                                Button(action: {
                                    self.theme = theme
                                }) {
                                    Text(theme.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(self.theme == theme ? Color.gray.opacity(0.3) : Color.clear)
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .onAppear {
                        isAnimating = true
                        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                            withAnimation {
                                selectedCharacter = (selectedCharacter + 1) % characters.count
                            }
                        }
                    }

                    VStack(spacing: 15) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
                                .frame(width: 40)

                            TextField("Username", text: $username)
                                .font(AppTheme.roundedFont(size: 18))
                                .padding()
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))
                                .background(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                                .cornerRadius(10)
                        }
                        .padding(4)
                        .background(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.1), radius: 5)

                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: preferences))
                                .frame(width: 40)

                            SecureField("Password", text: $password)
                                .font(AppTheme.roundedFont(size: 18))
                                .padding()
                                .foregroundColor(AppTheme.adaptiveTextColor(preferences: preferences))
                                .background(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                                .cornerRadius(10)
                        }
                        .padding(4)
                        .background(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.1), radius: 5)

                        if loginError {
                            Text("Try again! Wrong username or password")
                                .font(AppTheme.roundedFont(size: 16))
                                .foregroundColor(AppTheme.adaptiveErrorColor(preferences: preferences))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Demo Accounts:")
                                .font(AppTheme.roundedFont(size: 14, weight: .semibold))
                                .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: preferences))
                            
// default logins displayed so i dont forget
                            // remove for demo???
                            Text("🧒 Student: username 'yasming', password 'password'")
                            Text("👩‍🏫 Teacher: username 'teacher', password 'password'")
                        }
                        .font(AppTheme.roundedFont(size: 12))
                        .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: preferences))
                        .padding(.horizontal)

                        Button(action: performLogin) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Login")
                                    .font(AppTheme.roundedFont(size: 20, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(AppTheme.adaptivePrimaryColor(preferences: preferences))
                                    .shadow(Color: AppTheme.adaptivePrimaryColor(preferences: preferences).opacity(0.5), radius: 5)
                            )
                        }
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 30)

                    Spacer()

                    Button(action: { showRegister = true }) {
                        Text("New Student? Join Us!")
                            .font(AppTheme.roundedFont(size: 18, weight: .medium))
                            .foregroundColor(AppTheme.funPink)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(AppTheme.funPink, lineWidth: 2)
                            )
                    }
                    .padding(.bottom, 30)
                }
                .padding()
            }
            .sheet(isPresented: $showRegister) {
                RegisterView()
                    .environmentObject(authManager)
            }
        }
    }

    func performLogin() {
        SoundManager.shared.playClick()
        if authManager.login(username: username, password: password) {
            loginError = false
        } else {
            loginError = true
        }
    }
}

struct EnhancedTracingCanvasView: View {
    let letter: String
    @Binding var userDrawnPath: Path
    @Binding var userDrawnSegments: [Path]
    let showNumberedGuide: Bool
    let showArrows: Bool
    let showPath: Bool
    let isTrySampleMode: Bool
    @Binding var animateStroke: Bool
    @Binding var strokeProgress: CGFloat
    
    @State private var showGuidePulse = false
    @State private var guideOpacity = 1.0
    
    var body: some View {
        ZStack {
            //  dotted paper effect with subtle animation 4 background
            VStack(spacing: 15) {
                ForEach(0..<20, id: \.self) { _ in
                    HStack(spacing: 15) {
                        ForEach(0..<20, id: \.self) { _ in
                            Circle()
                                .fill(AppTheme.primaryColor.opacity(0.1))
                                .frame(width: 3, height: 3)
                                .scaleEffect(showGuidePulse ? 1.2 : 1.0)
                                .animation(
                                    Animation.easeInOut(duration: 2)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double.random(in: 0...2)),
                                    value: showGuidePulse
                                )
                        }
                    }
                }
            }
            .padding()
            .onAppear {
                showGuidePulse = true
            }
            
            // Letter to trace - giant and very faded in background for context
            Text(letter)
                .font(.system(size: 200, weight: .bold, design: .rounded))
                .foregroundColor(Color.gray.opacity(0.1))
                
            // Sample animation or reference path
            if isTrySampleMode {
                ZStack {
                    // Glowing effect under the stroke
                    if EnhancedLetterPathFactory.letterNeedsPenLifting(letter) {
                        // Use enhanced path with segments for pen lifting
                        EnhancedTracingAnimatedPathView(
                            letter: letter,
                            progress: strokeProgress
                        )
                    } else {
                        // Shadow/glow first
                        TracingAnimatedPathView(letter: letter, progress: strokeProgress)
                            .stroke(AppTheme.secondaryColor.opacity(0.3), lineWidth: 8)
                            .blur(radius: 6)
                        
                        // Main animated stroke
                        TracingAnimatedPathView(letter: letter, progress: strokeProgress)
                            .stroke(AppTheme.secondaryColor, lineWidth: 6)
                            .shadow(color: AppTheme.secondaryColor.opacity(0.5), radius: 3)
                    }
                }
            } else if showPath {
                TracingPathView(letter: letter)
                    .stroke(AppTheme.primaryColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 8]))
                    .opacity(0.7)
            }
            
            // User's drawn segments - completed paths
            ForEach(0..<userDrawnSegments.count, id: \.self) { index in
                userDrawnSegments[index]
                    .stroke(AppTheme.successColor, lineWidth: 6)
                    .shadow(color: AppTheme.successColor.opacity(0.5), radius: 2)
            }
            
            // Current drawing path - actively drawing
            userDrawnPath
                .stroke(AppTheme.successColor, lineWidth: 6)
                .shadow(Color: AppTheme.successColor.opacity(0.5), radius: 2)
            
            // Guides
            if showNumberedGuide && !isTrySampleMode {
                EnhancedNumberedPathGuideView(letter: letter)
                    .opacity(guideOpacity)
                    .onAppear {
                        // Pulse the guides to draw attention
                        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            guideOpacity = 0.7
                        }
                    }
            }
            
            if showArrows && !isTrySampleMode {
                DirectionalArrowsView(letter: letter, style: .enhanced)
                    .opacity(guideOpacity)
            }
            
            //  animated hand icon for the first guide point when starting
            // small n subtle but useful for some
            if showNumberedGuide && !isTrySampleMode && userDrawnSegments.isEmpty && userDrawnPath.isEmpty {
                GeometryReader { geometry in
                    let guidePoints = LetterPathFactory.letterPathDefinition(for: letter).guidePoints(geometry.size)
                    if !guidePoints.isEmpty {
                        Image(systemName: "hand.point.up.fill")
                            .font(.system(size: 30))
                            .foregroundColor(AppTheme.secondaryColor)
                            .position(guidePoints[0])
                            .offset(y: -40)
                            .opacity(showGuidePulse ? 1.0 : 0.5)
                            .scaleEffect(showGuidePulse ? 1.1 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: showGuidePulse
                            )
                    }
                }
            }
        }
    }
}
                    
struct EnhancedControlsView: View {
    @Binding var currentLetterIndex: Int
    let letters: [String]
    @Binding var showNumberedGuide: Bool
    @Binding var showArrows: Bool
    @Binding var showPath: Bool
    @Binding var isTrySampleMode: Bool
    @Binding var animationSpeed: Double
    let onReset: () -> Void
    let onToggleSample: () -> Void
    let onShowHelp: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            // Toggle controls in a rounded card
            VStack(spacing: 10) {
                HStack(spacing: 15) {
                    // Helper buttons
                    HelpToggleButton(
                        iconName: "figure.walk",
                        title: "Show Path",
                        isOn: $showPath,
                        Color: AppTheme.primaryColor,
                        disabled: isTrySampleMode
                    )
                    
                    HelpToggleButton(
                        iconName: "hand.point.up.fill",
                        title: "Show Numbers",
                        isOn: $showNumberedGuide,
                        Color: AppTheme.primaryColor,
                        disabled: isTrySampleMode
                    )
                    
                    HelpToggleButton(
                        iconName: "arrow.up.forward",
                        title: "Show Arrows",
                        isOn: $showArrows,
                        Color: AppTheme.primaryColor,
                        disabled: isTrySampleMode
                    )
                }
                
                // Sample mode slider if active
                if isTrySampleMode {
                    VStack(spacing: 5) {
                        Text("Speed: \(animationSpeed, specifier: "%.1f")x")
                            .font(AppTheme.roundedFont(size: 14))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: "tortoise")
                                .foregroundColor(.secondary)
                            
                            Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.25)
                                .tint(AppTheme.errorColor)
                            
                            Image(systemName: "hare")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 5)
            )
            
            // Action buttons
            HStack(spacing: 12) {
                // Help button
                ActionButton(
                    title: "Help",
                    icon: "questionmark.circle.fill",
                    Color: AppTheme.primaryColor,
                    action: onShowHelp
                )
                
                // Reset button
                ActionButton(
                    title: "Clear",
                    icon: "trash.fill",
                    Color: Color.red,
                    action: onReset,
                    disabled: isTrySampleMode
                )
                
                // Sample button
                ActionButton(
                    title: isTrySampleMode ? "Stop" : "Try",
                    icon: isTrySampleMode ? "stop.fill" : "play.fill",
                    Color: AppTheme.secondaryColor,
                    action: onToggleSample
                )
                
                // Navigation buttons
                HStack(spacing: 0) {
                    Button(action: {
                        SoundManager.shared.playClick()
                        if currentLetterIndex > 0 {
                            currentLetterIndex -= 1
                        }
                    }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(currentLetterIndex > 0 && !isTrySampleMode ?
                                        AppTheme.primaryColor : Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .disabled(currentLetterIndex == 0 || isTrySampleMode)
                    
                    Button(action: {
                        SoundManager.shared.playClick()
                        if currentLetterIndex < letters.count - 1 {
                            currentLetterIndex += 1
                        }
                    }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(currentLetterIndex < letters.count - 1 && !isTrySampleMode ?
                                        AppTheme.primaryColor : Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .disabled(currentLetterIndex == letters.count - 1 || isTrySampleMode)
                }
                .padding(.leading, 5)
            }
            .padding(.vertical, 10)
        }
    }
}
                    
struct EnhancedFeedbackView: View {
    let score: Double
    let character: String
    let onContinue: () -> Void
    
    var body: some View {
        HStack {
            // Character reaction
            Text(getCharacterReaction())
                .font(.system(size: 40))
                .offset(y: score >= 70 ? -5 : 0)
                .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: score >= 70)
            
            VStack(alignment: .leading, spacing: 5) {
                // Accuracy text
                Text("Accuracy: \(Int(score))%")
                    .font(AppTheme.roundedFont(size: 18, weight: .bold))
                    .foregroundColor(getFeedbackColor(score: score))
                
                // Feedback message
                Text(getFeedbackMessage(score: score))
                    .font(AppTheme.roundedFont(size: 14))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Continue button
            Button(action: {
                SoundManager.shared.playClick()
                onContinue()
            }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(AppTheme.primaryColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5)
        )
        .padding(.horizontal)
    }
    
    private func getFeedbackColor(score: Double) -> Color {
        if score >= 80 { return AppTheme.successColor }
        else if score >= 60 { return AppTheme.secondaryColor }
        else { return AppTheme.errorColor }
    }
    
    private func getFeedbackMessage(score: Double) -> String {
        if score >= 85 { return "Amazing! Perfect tracing!" }
        else if score >= 70 { return "Good job! You're doing great!" }
        else if score >= 50 { return "Nice try! Follow the dots carefully." }
        else { return "Try again! Watch the numbered dots." }
    }
    
    private func getCharacterReaction() -> String {
        if score >= 85 { return character + " 🎉" }
        else if score >= 70 { return character + " 😊" }
        else if score >= 50 { return character + " 🙂" }
        else { return character + " 🤔" }
    }
}

struct HelpPopupView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    SoundManager.shared.playClick()
                    onDismiss()
                }

            // Help popup content (shifted left)
            VStack(spacing: 15) {
                // Title
                HStack {
                    Text("How to Trace Letters")
                        .font(AppTheme.roundedFont(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.primaryColor)

                    Spacer()

                    Button(action: {
                        SoundManager.shared.playClick()
                        onDismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(AppTheme.primaryColor)
                    }
                }

                // 'Instructions'
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        InstructionItem(
                            icon: "1.circle.fill",
                            title: "Follow the Dots",
                            description: "Start at dot 1, then go to 2, 3, and so on."
                        )

                        InstructionItem(
                            icon: "arrow.up.forward.circle.fill",
                            title: "Watch the Arrows",
                            description: "Arrows show you which way to go."
                        )

                        InstructionItem(
                            icon: "hand.draw.fill",
                            title: "Trace the Letter",
                            description: "Use your finger to trace over the dotted letter."
                        )

                        InstructionItem(
                            icon: "play.fill",
                            title: "Watch a Demo",
                            description: "Tap 'Try' to see how to trace the letter."
                        )

                        InstructionItem(
                            icon: "trash.fill",
                            title: "Start Over",
                            description: "Tap 'Clear' if you want to try again."
                        )
                    }
                    .padding(.horizontal, 10)
                }
                .frame(height: 280)

                // Close button
                Button(action: {
                    SoundManager.shared.playClick()
                    onDismiss()
                }) {
                    Text("Let's Trace!")
                        .font(AppTheme.roundedFont(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 200)
                        .background(AppTheme.primaryColor)
                        .cornerRadius(25)
                        .shadow(radius: 5)
                }

                Spacer().frame(height: 10)
            }
            .padding(25)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.white)
            )
            .shadow(radius: 15)
            .padding(.horizontal, 30)
            .offset(x: -11) // (shift left where it looks better)
        }
    }
}

// MAIN!!
// DETERMINES WHICH VIEW
// IN MAIN APP DEFINITION
// IMPORTANT
struct AppStartView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        if authManager.currentUser?.role == .teacher {
            // only show on teacher
            TeacherDashboardView()
                .environmentObject(authManager)
        } else {
            // shows full student interface
            StudentMainView()
                .environmentObject(authManager)
        }
    }
}

struct StudentMainView: View {
    @State private var selectedSidebarItem: SidebarItem = .home
    @State private var showPath: Bool = true
    
    var body: some View {
        TabView {
            HomeDashboardView(selectedSidebarItem: $selectedSidebarItem)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            FocusModeView()
                .tabItem {
                    Label("Focus", systemImage: "scope")
                }
            MyRewardsView()
                .tabItem {
                    Label("Rewards", systemImage: "star")
                }
            TracingAppView(letter: "A", showPath: $showPath)
                .tabItem {
                    Label("Practice", systemImage: "pencil")
                }
        }
    }
}

// Full TracingAppView with my new overlap fixes
struct TracingAppView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var practiceLetters: [String]?
    var selectedLetter: String? = nil

    @State private var userDrawnPath = Path()
    @State private var userDrawnPoints: [CGPoint] = []
    @State private var testScores: [Double?] = []
    @State private var currentLetterIndex = 0
    @State private var isDrawingComplete = false
    @State private var showNumberedGuide = true
    @State private var showArrows = true
    @Binding var showPath: Bool
    @State private var accuracyScore: Double = 0
    @State private var userDrawnSegments: [Path] = []
    @State private var allUserDrawnPoints: [[CGPoint]] = []
    @State private var strokeProgress: CGFloat = 0
    @State private var animateStroke = false
    @State private var currentStrokeSegment = 0
    @State private var animationSpeed: Double = 1.0
    @State private var isTrySampleMode = false
    @State private var showCelebrationOverlay = false
    @State private var rewardMessage = ""
    @State private var helpPopupVisible = false
    @State private var showGuidePulse = false
    @State private var isDrawing = false
    @State private var lastScore: Double = 0
    @State private var showAccessibilitySettings = false
    @State private var recentRewards: [String] = []

    init(letter: String, showPath: Binding<Bool>, practiceLetters: [String]? = nil) {
        self.selectedLetter = letter
        self.practiceLetters = practiceLetters
        _showPath = showPath
    }

    private var studentPerformance: StudentPerformance? {
        guard let user = authManager.currentUser, user.role == .student else { return nil }
        return authManager.currentPerformance
    }

    var letters: [String] {
        practiceLetters ?? ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                headerSection
                progressBarSection
                letterSelectionSection
                tracingCanvasSection(height: min(geometry.size.height * 0.45, 350))
                Spacer(minLength: 5)
                controlsSection(padding: geometry.safeAreaInsets.bottom + 5)
            }
            .offset(x: -12)
            .padding(.top, geometry.safeAreaInsets.top > 60 ? geometry.safeAreaInsets.top - 60 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.backgroundColor)
            .onChange(of: currentLetterIndex) { _, _ in resetDrawing() }
            .onAppear {
                showGuidePulse = true
                testScores = Array(repeating: nil, count: letters.count)

                if let user = authManager.currentUser {
                    let studentId = user.id
                    let allScores = authManager.getStudentSQLiteScores(for: studentId)

                    // Update the progress bar
                    testScores = letters.map { allScores[$0] ?? nil }

                    // Restore last practiced letter if available
                    if let last = authManager.currentPerformance?.lastLetterPracticed,
                       let index = letters.firstIndex(of: last) {
                        currentLetterIndex = index
                    }

                    // Save last practiced letter if not yet saved
                    if authManager.currentPerformance?.lastLetterPracticed == nil {
                        let currentLetter = letters[currentLetterIndex]
                        authManager.currentPerformance?.lastLetterPracticed = currentLetter

                        SQLiteManager.shared.saveStudentPerformance(
                            id: user.id,
                            name: authManager.currentPerformance?.studentName ?? user.username,
                            totalRewards: authManager.currentPerformance?.totalRewards ?? 0,
                            streak: authManager.currentPerformance?.consecutiveDayStreak ?? 0,
                            lastPracticeDate: authManager.currentPerformance?.lastPracticeDate ?? Date()
                        )
                    }
                }
            }
            .overlay(celebrationOverlay)
            .overlay(feedbackOverlay(safeArea: geometry.safeAreaInsets))
            .sheet(isPresented: $showAccessibilitySettings) {
                if let user = authManager.currentUser {
                    AccessibilitySettingsView(currentPreferences: user.preferences)
                        .environmentObject(authManager)
                }
            }
        }
    }

    // the subviews

    private var headerSection: some View {
        VStack(spacing: 0) {
            EnhancedHeaderView(
                onLogout: { authManager.logout() },
                onShowSettings: {
                    SoundManager.shared.playClick()
                    showAccessibilitySettings = true
                }
            )
        }
    }

    private var progressBarSection: some View {
        MultiLetterProgressBar(scores: testScores)
            .padding(.top, 8)
    }

    private var letterSelectionSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(0..<letters.count, id: \.self) { index in
                    Button(action: {
                        currentLetterIndex = index
                        resetDrawing()
                        
                        // Save selected letter as last practiced
                        if let user = authManager.currentUser {
                            authManager.currentPerformance?.lastLetterPracticed = letters[index]
                            SQLiteManager.shared.saveStudentPerformance(
                                id: user.id,
                                name: authManager.currentPerformance?.studentName ?? user.username,
                                totalRewards: authManager.currentPerformance?.totalRewards ?? 0,
                                streak: authManager.currentPerformance?.consecutiveDayStreak ?? 0,
                                lastPracticeDate: authManager.currentPerformance?.lastPracticeDate ?? Date()
                            )
                        }
                    }) {
                        Text(letters[index])
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(currentLetterIndex == index ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(currentLetterIndex == index ? AppTheme.accentColor : Color.gray.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 4)
    }

    private func tracingCanvasSection(height: CGFloat) -> some View {
        ZStack {
            EnhancedTracingCanvasView(
                letter: letters[currentLetterIndex],
                userDrawnPath: $userDrawnPath,
                userDrawnSegments: $userDrawnSegments,
                showNumberedGuide: showNumberedGuide,
                showArrows: showArrows,
                showPath: showPath,
                isTrySampleMode: isTrySampleMode,
                animateStroke: $animateStroke,
                strokeProgress: $strokeProgress
            )
            .gesture(drawingGesture)
        }
        .frame(height: height)
        .padding(.horizontal, 20)
    }

    private func controlsSection(padding: CGFloat) -> some View {
        EnhancedControlsView(
            currentLetterIndex: $currentLetterIndex,
            letters: letters,
            showNumberedGuide: $showNumberedGuide,
            showArrows: $showArrows,
            showPath: $showPath,
            isTrySampleMode: $isTrySampleMode,
            animationSpeed: $animationSpeed,
            onReset: resetDrawing,
            onToggleSample: toggleSampleMode,
            onShowHelp: {
                SoundManager.shared.playClick()
                helpPopupVisible = true
            }
        )
        .padding(.vertical, 10)
        .padding(.bottom, padding)
    }

    private var celebrationOverlay: some View {
        ZStack {
            if showCelebrationOverlay {
                Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                ZStack {
                    ConfettiView().allowsHitTesting(false)
                    EnhancedCelebrationView(
                        message: rewardMessage,
                        score: accuracyScore,
                        letter: letters[currentLetterIndex],
                        onDismiss: {
                            withAnimation { showCelebrationOverlay = false }
                        },
                        characterEmoji: authManager.currentUser?.preferences.characterEmoji ?? "🦊"
                    )
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.85)
                    .offset(x: -15, y: -70)
                }
            }
            if helpPopupVisible {
                HelpPopupView(onDismiss: { helpPopupVisible = false })
                    .zIndex(2)
            }
        }
    }

    private func feedbackOverlay(safeArea: EdgeInsets) -> some View {
        Group {
            if isDrawingComplete {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        EnhancedFeedbackView(
                            score: accuracyScore,
                            character: authManager.currentUser?.preferences.characterEmoji ?? "🦊",
                            onContinue: {
                                if let user = authManager.currentUser {
                                    let currentLetter = letters[currentLetterIndex]
                                    let score = accuracyScore > 0 ? accuracyScore : 85.0
                                    
                                    authManager.updateStudentPerformanceWithSQLite(
                                        studentId: user.id,
                                        letter: currentLetter,
                                        score: score
                                    )
                                    
                                    if var perf = authManager.currentPerformance {
                                        perf.lastLetterPracticed = currentLetter
                                        SQLiteManager.shared.saveStudentPerformance(
                                            id: user.id,
                                            name: perf.studentName,
                                            totalRewards: perf.totalRewards,
                                            streak: perf.consecutiveDayStreak,
                                            lastPracticeDate: Date()
                                        )
                                    }
                                }
                                isDrawingComplete = false
                            }
                        )
                        .padding(.bottom, max(safeArea.bottom, 20) + 10)
                        .transition(.move(edge: .bottom))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .zIndex(1)
        .sheet(isPresented: $showAccessibilitySettings) {
            if let user = authManager.currentUser {
                AccessibilitySettingsView(currentPreferences: user.preferences)
                    .environmentObject(authManager)
            }
        }
    }
    // Gesture for drawing
    private var drawingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isTrySampleMode {
                    let point = value.location
                    if userDrawnPath.isEmpty {
                        userDrawnPath.move(to: point)
                        userDrawnPoints = [point]
                        SoundManager.shared.playDrawSound()
                    } else {
                        userDrawnPath.addLine(to: point)
                        userDrawnPoints.append(point)
                        if userDrawnPoints.count % 5 == 0 {
                            SoundManager.shared.playDrawSound()
                        }
                    }
                    isDrawing = true
                }
            }
            .onEnded { _ in
                if !isTrySampleMode && !userDrawnPath.isEmpty {
                    userDrawnSegments.append(userDrawnPath)
                    allUserDrawnPoints.append(userDrawnPoints)

                    // Calculate accuracy
                    let score = checkDrawingAccuracy()
                    accuracyScore = score
                    isDrawingComplete = true

                    if let user = authManager.currentUser {
                        let currentLetter = letters[currentLetterIndex]

                        // Rewards
                        awardRewards(for: currentLetter, with: score, to: user.id, authManager: authManager)

                        // Performance update
                        if user.role == .student {
                            authManager.updateStudentPerformanceWithSQLite(
                                studentId: user.id,
                                letter: currentLetter,
                                score: score
                            )

                            // Set last practiced letter
                            authManager.currentPerformance?.lastLetterPracticed = currentLetter
                            SQLiteManager.shared.saveStudentPerformance(
                                id: user.id,
                                name: authManager.currentPerformance?.studentName ?? user.username,
                                totalRewards: authManager.currentPerformance?.totalRewards ?? 0,
                                streak: authManager.currentPerformance?.consecutiveDayStreak ?? 0,
                                lastPracticeDate: Date()
                            )

                            if testScores.indices.contains(currentLetterIndex) {
                                testScores[currentLetterIndex] = score
                            }
                        }
                    }

                    // Reset for next stroke
                    userDrawnPath = Path()
                    userDrawnPoints = []
                }
                isDrawing = false
            }
    }

    // Reset drawing state
    private func resetDrawing() {
        userDrawnPath = Path()
        userDrawnPoints = []
        userDrawnSegments = []
        allUserDrawnPoints = []
        isDrawingComplete = false
        showCelebrationOverlay = false
        accuracyScore = 0
        stopAnimation()
    }

    // Stop stroke animation
    private func stopAnimation() {
        animateStroke = false
        strokeProgress = 0
    }

    // Toggle sample mode
    private func toggleSampleMode() {
        SoundManager.shared.playClick()
        isTrySampleMode.toggle()
        
        if isTrySampleMode {
            // Reset and start animation
            resetDrawing()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                startStrokeAnimation()
            }
        } else {
            stopAnimation()
            resetDrawing()
        }
    }

    // Start stroke animation
    private func startStrokeAnimation() {
        strokeProgress = 0
        animateStroke = true
        
        // Reset stroke segments for animation
        currentStrokeSegment = 0
        
        // Calculate interval based on animation speed
        let baseInterval = 0.01
        let adjustedInterval = baseInterval / animationSpeed
        
        // Create and start the animation timer
        Timer.scheduledTimer(withTimeInterval: adjustedInterval, repeats: true) { timer in
            if !animateStroke {
                timer.invalidate()
                return
            }
            
            if strokeProgress < 1.0 {
                // Increment progress based on speed
                strokeProgress += 0.005 * CGFloat(animationSpeed)
                
                // Trigger drawing sound at intervals for realism
                if Int(strokeProgress * 100) % 20 == 0 {
                    SoundManager.shared.playDrawSound()
                }
            } else {
                timer.invalidate()
                
                // Restart animation after a short delay if still in demo mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isTrySampleMode {
                        strokeProgress = 0
                        startStrokeAnimation()
                    }
                }
            }
        }
    }
    
    // Award reward function
    private func awardRewards(for letter: String, with score: Double, to studentId: String, authManager: AuthManager) {
        // recommended by website
        // ensures student performance and letter index is correct
        guard let studentPerformance = authManager.currentPerformance,
              let letterIndex = studentPerformance.letterPerformances.firstIndex(where: { $0.letter == letter }) else {
            return // Exit the function if either condition is nil
        }

        let performance = studentPerformance
        let letterPerformance = performance.letterPerformances[letterIndex]

        let previousAverage = letterPerformance.averageScore
        let previousAttempts = letterPerformance.attempts

        var allRewards: [String] = []

        // Collect all rewards
        if previousAttempts == 0 {
            allRewards.append("🎯")
        }
        if score >= 90 {
            allRewards.append("⭐️")
            if score >= 95 { allRewards.append("🌟") }
            if score >= 98 { allRewards.append("🏆") }
        }
        if previousAttempts > 0 && score > previousAverage + 15 {
            allRewards.append("📈")
        }
        if score >= 85 && previousAttempts >= 2 {
            if !letterPerformance.isMastered || score > previousAverage {
                allRewards.append("🎨")
            }
        }
        if performance.consecutiveDayStreak > 0 && performance.consecutiveDayStreak % 3 == 0 {
            allRewards.append("🔥")
        }
        if Bool.random() && score >= 80 {
            allRewards.append(["✏️", "🖌️", "🎊", "🎭", "🎲"].randomElement()!)
        }

        // Remove recently used rewards to encourage variety
        let filteredRewards = allRewards.filter { !recentRewards.contains($0) }

        // Pick from filtered list, or fallback to full list if all have been used
        let finalRewardPool = filteredRewards.isEmpty ? allRewards : filteredRewards
        let selectedRewards = Array(finalRewardPool.shuffled().prefix(3))

        // Update recentRewards (limit to last 10)
        recentRewards.append(contentsOf: selectedRewards)
        recentRewards = Array(recentRewards.suffix(10))

        // Give reward
        PerformanceManager.shared.awardRewards(for: letter, with: score, to: studentId)

        // Set reward message
        // Makes seem more encouraging for student
        if score >= 95 {
            rewardMessage = "Wonderful Tracing!"
        } else if score >= 85 {
            rewardMessage = "Great Job!"
        } else if score >= 70 {
            rewardMessage = "Nice Work!"
        } else if score > lastScore + 15 {
            rewardMessage = "Big Improvement!"
        }

        if score >= 85 || score > lastScore + 15 {
            let delay = DispatchTime.now() + 0.5

            // Show the overlay after delay
            DispatchQueue.main.asyncAfter(deadline: delay) {
                showCelebrationOverlay = true
            }

            // Trigger animation to sync with the overlay appearance
            DispatchQueue.main.asyncAfter(deadline: delay + 0.05) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    _ = showCelebrationOverlay
                }
            }
        }

        lastScore = score

        if !selectedRewards.isEmpty {
            SoundManager.shared.playCelebration()
        } else if score >= 80 {
            SoundManager.shared.playComplete()
        } else {
            SoundManager.shared.playSuccess()
        }
    }
    
    private func averagePoint(from points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let total = points.reduce(CGPoint.zero) { sum, point in
            CGPoint(x: sum.x + point.x, y: sum.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(points.count), y: total.y / CGFloat(points.count))
    }

    private func checkDrawingAccuracy() -> Double {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
        
        // Get the UIBezierPath of the actual path shown on screen
        let letterPathDefinition = LetterPathFactory.letterPathDefinition(for: letters[currentLetterIndex])
        let visiblePath = letterPathDefinition.path(rect)
        let bezierPath = UIBezierPath(cgPath: visiblePath.cgPath)
        
        // Create refernce points from the visible path
        let pointCount = 150
        var referencePath: [CGPoint] = []
        for i in 0...pointCount {
            let t = CGFloat(i) / CGFloat(pointCount)
            referencePath.append(bezierPath.point(at: t))
        }
        
        if referencePath.isEmpty || allUserDrawnPoints.isEmpty {
            return 70 // safe fallback score
        }
        
        var combinedUserPoints: [CGPoint] = []
        for pointArray in allUserDrawnPoints {
            combinedUserPoints.append(contentsOf: pointArray)
        }
        
        if combinedUserPoints.isEmpty {
            return 70
        }
        
        // Sample user points for better comparison
        let sampledUserPoints = samplePoints(from: combinedUserPoints, count: min(300, combinedUserPoints.count))
        
        // Scoring tolerances (less strict)
        let generousTolerance: CGFloat = 40
        let lenientTolerance: CGFloat = 25

        // 1 : how well does the user follow the reference path?
        var pathFollowedLoosely = 0
        var pathFollowedWell = 0
        for refPoint in referencePath {
            let minDistance = sampledUserPoints.map { hypot($0.x - refPoint.x, $0.y - refPoint.y) }.min() ?? .infinity
            if minDistance <= generousTolerance { pathFollowedLoosely += 1 }
            if minDistance <= lenientTolerance { pathFollowedWell += 1 }
        }

        let coverageScore = (Double(pathFollowedLoosely) / Double(referencePath.count)) * 100
        let precisionScore = (Double(pathFollowedWell) / Double(referencePath.count)) * 100

        // 2 : how close are user points to the correct path?
        var userPointsNearPath = 0
        var userPointsPrecise = 0
        for userPoint in sampledUserPoints {
            let minDistance = referencePath.map { hypot(userPoint.x - $0.x, userPoint.y - $0.y) }.min() ?? .infinity
            if minDistance <= generousTolerance { userPointsNearPath += 1 }
            if minDistance <= lenientTolerance { userPointsPrecise += 1 }
        }

        let accuracyScore = (Double(userPointsNearPath) / Double(sampledUserPoints.count)) * 100
        let precisionUserScore = (Double(userPointsPrecise) / Double(sampledUserPoints.count)) * 100

        // 3: multistroke penalty (minimal)
        var strokePenalty = 0.0
        let isMultiStrokeLetter = EnhancedLetterPathFactory.letterNeedsPenLifting(letters[currentLetterIndex])
        if isMultiStrokeLetter, let enhancedDef = EnhancedLetterPathFactory.getEnhancedLetterPath(for: letters[currentLetterIndex]) {
            let expectedStrokes = enhancedDef.strokeSegments(CGSize(width: 300, height: 400)).count
            let completedStrokes = allUserDrawnPoints.count
            if completedStrokes < expectedStrokes {
                strokePenalty = Double(expectedStrokes - completedStrokes) * 2.0
            }
        }

        // if shape drawn correctly but skewed
        // reward a little without penalising
        var skewBonus = 0.0
        if coverageScore > 80 {
            let userCenter = averagePoint(from: sampledUserPoints)
            let refCenter = averagePoint(from: referencePath)
            let dx = abs(userCenter.x - refCenter.x)
            let dy = abs(userCenter.y - refCenter.y)

            if dx < 100 && dy < 100 {
                let skewFactor = max(0, 1.0 - ((dx + dy) / 200.0)) // normalized between 0–1
                skewBonus = 4.0 * skewFactor
            }
        }

        // Final base score calculation (path-following is dominant)
        let baseScore = (
            coverageScore * 0.4 +         // Did they trace the whole shape?
            accuracyScore * 0.25 +        // Were user points close to the path?
            precisionScore * 0.2 +        // How well did they stay on the line?
            precisionUserScore * 0.15     // Were their strokes consistent?
        ) - strokePenalty + skewBonus     // Add small bonus for correct shape position

        // Optional bonus curve for good scores
        var curvedScore = baseScore
        if baseScore > 85 {
            curvedScore += (100 - baseScore) * 0.1
        } else if baseScore > 70 {
            curvedScore += (baseScore - 70) * 0.15
        }

        let finalScore = min(100, max(0, curvedScore))

        // Play appropriate sound based on score
        if finalScore > 88 {
            SoundManager.shared.playComplete()
        } else if finalScore > 65 {
            SoundManager.shared.playSuccess()
        }

        // Save score to database if logged in as a student
        if let user = authManager.currentUser, user.role == .student {
            authManager.updateStudentPerformanceWithSQLite(
                studentId: user.id,
                letter: letters[currentLetterIndex],
                score: finalScore
            )
        }

        return finalScore
    }

    // Helper function to find bounding box of a set of points
    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }
        
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity
        
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    // calculates shape similarity
    private func calculateShapeSimilarity(userBounds: CGRect, refBounds: CGRect) -> Double {
        // Compare aspect ratios (just in case cases)
        let userAspect = userBounds.width / max(userBounds.height, 1)
        let refAspect = refBounds.width / max(refBounds.height, 1)
        
        let aspectMatch = 1.0 - min(abs(userAspect - refAspect) / max(refAspect, 1), 1.0)
        
        // compare centers
        let userCenter = CGPoint(x: userBounds.midX, y: userBounds.midY)
        let refCenter = CGPoint(x: refBounds.midX, y: refBounds.midY)
        
        let maxDistance = sqrt(pow(300.0, 2) + pow(400.0, 2))
        let centerDistance = sqrt(pow(userCenter.x - refCenter.x, 2) + pow(userCenter.y - refCenter.y, 2))
        let positionMatch = 1.0 - min(centerDistance / (maxDistance / 2), 1.0)
        
        // Compare sizes
        let userSize = max(userBounds.width, userBounds.height)
        let refSize = max(refBounds.width, refBounds.height)
        let sizeMatch = 1.0 - min(abs(userSize - refSize) / max(refSize, 1), 1.0)
        
        return aspectMatch * 0.4 + positionMatch * 0.3 + sizeMatch * 0.3
    }
    
    // points sampled EVENLY
    private func samplePoints(from points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > 1, count > 1 else { return points }
        var result: [CGPoint] = []
        var totalLength: CGFloat = 0
        for i in 1..<points.count {
            totalLength += hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y)
        }
        var currentLength: CGFloat = 0
        let step = totalLength / CGFloat(count - 1)
        result.append(points.first!)
        var currentIndex = 0
        var targetLength = step
        while targetLength <= totalLength && result.count < count && currentIndex < points.count - 1 {
            let segmentLength = hypot(points[currentIndex+1].x - points[currentIndex].x,
                                      points[currentIndex+1].y - points[currentIndex].y)
            if currentLength + segmentLength >= targetLength {
                let remainingLength = targetLength - currentLength
                let percentage = remainingLength / segmentLength
                let newPoint = CGPoint(
                    x: points[currentIndex].x + (points[currentIndex+1].x - points[currentIndex].x) * percentage,
                    y: points[currentIndex].y + (points[currentIndex+1].y - points[currentIndex].y) * percentage
                )
                result.append(newPoint)
                targetLength += step
            } else {
                currentLength += segmentLength
                currentIndex += 1
            }
        }
        if result.count < count {
            result.append(points.last!)
        }
        return result
    }
}

struct UserScoresGrid: View {
    let userScores: [String: Double?]
    let alphabet: [String]
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 80))
        ], spacing: 15) {
            ForEach(alphabet, id: \.self) { letter in
                VStack {
                    Text(letter)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if let score = userScores[letter] ?? nil {
                        Text(String(format: "%.1f", score))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(ColorForScore(score))
                    } else {
                        Text("Not practiced")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(userScores[letter] != nil ? Color(.secondarySystemBackground) : Color(.tertiarySystemBackground))
                )
            }
        }
    }
    
    private func ColorForScore(_ score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .orange }
        else { return .red }
    }
}

struct UserScoresSummary: View {
    let userScores: [String: Double?]
    let alphabet: [String]
    
    private var practicedCount: Int {
        userScores.values.compactMap { $0 }.count
    }
    
    private var averageScore: Double {
        let scores = userScores.values.compactMap { $0 }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / Double(scores.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Letters practiced: \(practicedCount)/26")
                        .font(.subheadline)
                    
                    if practicedCount > 0 {
                        Text("Average score: \(String(format: "%.1f", averageScore))%")
                            .font(.subheadline)
                            .foregroundColor(ColorForScore(averageScore))
                    }
                }
                
                Spacer()
                
                // Progress circle
                if practicedCount > 0 {
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 8)
                            .opacity(0.3)
                            .foregroundColor(.gray)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(averageScore/100, 1.0)))
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                            .foregroundColor(ColorForScore(averageScore))
                            .rotationEffect(Angle(degrees: 270.0))
                        
                        Text("\(Int(averageScore))%")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(width: 50, height: 50)
                }
            }
            
            // Letter score indicators
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(alphabet, id: \.self) { letter in
                        ZStack {
                            Circle()
                                .fill(scoreColor(for: letter))
                                .frame(width: 30, height: 30)
                            
                            Text(letter)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
    }
    
    private func scoreColor(for letter: String) -> Color {
        guard let score = userScores[letter] ?? nil else {
            return Color.gray.opacity(0.3)
        }
        
        return ColorForScore(score)
    }
    
    private func ColorForScore(_ score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .orange }
        else { return .red }
    }
}

// includes settings button
struct EnhancedHeaderView: View {
    @EnvironmentObject var authManager: AuthManager
    var character: String {
        return authManager.currentUser?.preferences.characterEmoji ?? "🦊" // (fox always base case)
    }
    let onLogout: () -> Void
    var onShowSettings: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            AppTheme.primaryColor.opacity(0.2)
            
            HStack {
                // Character avatar
                Text(character)
                    .font(.system(size: 40))
                    .padding(.horizontal, 5)
                
                // User info
                if let user = authManager.currentUser {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hi, \(user.fullName.isEmpty ? user.username : user.fullName)!")
                            .font(AppTheme.roundedFont(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("Let's trace!")
                            .font(AppTheme.roundedFont(size: 16))
                            .foregroundColor(.primary.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Settings button
                Button(action: onShowSettings) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("Settings")
                    }
                    .font(AppTheme.roundedFont(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.primaryColor)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(AppTheme.primaryColor, lineWidth: 1)
                            .opacity(0.5)
                    )
                }
                .padding(.trailing, 8)
                
                // Logout button
                Button(action: onLogout) {
                    Label("Exit", systemImage: "arrow.right.square.fill")
                        .font(AppTheme.roundedFont(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.errorColor)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppTheme.errorColor.opacity(0.1))
                        )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 70)
    }
}

// Letter progress tile (more childfriendly vers)
struct LetterProgressTile: View {
    let performance: LetterPerformance
    
    var body: some View {
        VStack(spacing: 5) {
            // Letter display
            Text(performance.letter)
                .font(AppTheme.roundedFont(size: 30, weight: .bold))
                .foregroundColor(performance.attempts > 0 ? .white : .gray)
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            performance.attempts == 0 ? Color.gray.opacity(0.2) :
                                performance.isMastered ? AppTheme.successColor :
                                performance.averageScore >= 70 ? AppTheme.secondaryColor :
                                AppTheme.primaryColor
                        )
                )
                .overlay(
                    Group {
                        if performance.isMastered {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .offset(x: 20, y: -20)
                        }
                    }
                )
            
            // Progress indicator
            if performance.attempts > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<min(performance.attempts, 5), id: \.self) { _ in
                        Circle()
                            .fill(progressColor(performance.averageScore))
                            .frame(width: 6, height: 6)
                    }
                    
                    if performance.attempts > 5 {
                        Text("+\(performance.attempts - 5)")
                            .font(AppTheme.roundedFont(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("New")
                    .font(AppTheme.roundedFont(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 2)
        )
    }
}

// detailed view for letter performance
struct LetterDetailView: View {
    let performance: LetterPerformance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Header with letter
            HStack {
                Text(performance.letter)
                    .font(AppTheme.roundedFont(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(
                                performance.isMastered ? AppTheme.successColor :
                                    performance.averageScore >= 70 ? AppTheme.secondaryColor :
                                    AppTheme.primaryColor
                            )
                    )
                
                VStack(alignment: .leading) {
                    Text(performance.isMastered ? "Mastered!" : "In Progress")
                        .font(AppTheme.roundedFont(size: 18, weight: .bold))
                        .foregroundColor(
                            performance.isMastered ? AppTheme.successColor :
                                performance.averageScore >= 70 ? AppTheme.secondaryColor :
                                AppTheme.primaryColor
                        )
                    
                    Text("Practiced \(performance.attempts) times")
                        .font(AppTheme.roundedFont(size: 14))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if performance.attempts > 0 {
                    VStack {
                        Text("\(Int(performance.averageScore))%")
                            .font(AppTheme.roundedFont(size: 24, weight: .bold))
                            .foregroundColor(progressColor(performance.averageScore))
                        
                        Text("Score")
                            .font(AppTheme.roundedFont(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Progress history
            if performance.scores.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Progress History")
                        .font(AppTheme.roundedFont(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    ProgressHistoryGraph(scores: performance.scores)
                        .frame(height: 100)
                }
            }
            
            // Rewards earned
            if !performance.rewards.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Rewards")
                        .font(AppTheme.roundedFont(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    HStack {
                        ForEach(performance.rewards, id: \.self) { reward in
                            Text(reward)
                                .font(.system(size: 30))
                        }
                    }
                }
            }
            
            // Last practiced
            Text("Last practiced: \(performance.lastPracticed.formatted(date: .abbreviated, time: .omitted))")
                .font(AppTheme.roundedFont(size: 14))
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(radius: 5)
        )
    }
}

struct WrapRewardsView: View {
    let rewards: [String]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(rewards, id: \.self) { reward in
                Text(reward)
                    .font(.largeTitle)
            }
        }
        .padding(.top, 8)
    }
}

struct RewardsDashboardView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Letter Rewards")
                    .font(.largeTitle.bold())

                if let user = authManager.currentUser,
                   let performance = authManager.currentPerformance {
                    ForEach(performance.letterPerformances.sorted { $0.letter < $1.letter }) { letterPerf in
                        if !letterPerf.rewards.isEmpty {
                            DisclosureGroup("Letter \(letterPerf.letter) - \(letterPerf.rewards.count) reward\(letterPerf.rewards.count == 1 ? "" : "s")") {
                                WrapRewardsView(rewards: letterPerf.rewards)
                            }
                            .padding()
                            .background(AppTheme.adaptiveCardBackgroundColor(preferences: authManager.currentUser?.preferences))
                            .cornerRadius(12)
                        }
                    }
                } else {
                    Text("No rewards found.")
                        .foregroundColor(.gray)
                }
            }
            .padding()
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(AppTheme.roundedFont(size: 16, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : AppTheme.secondaryColor)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? AppTheme.secondaryColor : AppTheme.secondaryColor.opacity(0.1))
                )
        }
    }
}

struct EnhancedRewardCard: View {
    let letter: String
    let rewards: [String]
    let animate: Bool
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 15) {
            // Letter header with rewards count
            Button(action: {
                SoundManager.shared.playClick()
                withAnimation(.spring()) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(AppTheme.primaryColor)
                            .frame(width: 50, height: 50)
                        
                        Text(letter)
                            .font(AppTheme.roundedFont(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Letter \(letter)")
                            .font(AppTheme.roundedFont(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("\(rewards.count) rewards")
                            .font(AppTheme.roundedFont(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(AppTheme.secondaryColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.secondaryColor)
                    }
                }
            }
            
            // Rewards grid (if expanded)
            if isExpanded {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 70, maximum: 80))
                ], spacing: 12) {
                    ForEach(rewards.indices, id: \.self) { index in
                        RewardBubble(
                            emoji: rewards[index],
                            animate: animate,
                            delay: Double(index) * 0.05
                        )
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        )
        .opacity(animate ? 1 : 0)
        .offset(y: animate ? 0 : 20)
        .transition(.opacity)
    }
}


struct RewardBubble: View {
    let emoji: String
    let animate: Bool
    let delay: Double
    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.secondaryColor.opacity(0.15))
                .frame(width: 60, height: 60)
            
            Text(emoji)
                .font(.system(size: 28))
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring()) {
                    scale = 1.0
                }
                
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    rotation = 5
                }
            }
        }
        .onChange(of: animate) { _, newValue in
            if !newValue {
                scale = 0.5
                rotation = 0
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring()) {
                        scale = 1.0
                    }
                    
                    withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        rotation = 5
                    }
                }
            }
        }
    }
}

struct AlphabetRewardsGrid: View {
    let earnedRewards: [String: [String]]
    let animate: Bool
    let alphabet = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 70, maximum: 80))
            ], spacing: 15) {
                ForEach(alphabet, id: \.self) { letter in
                    if let rewards = earnedRewards[letter], !rewards.isEmpty {
                        AlphabetLetterTile(letter: letter, rewards: rewards, animate: animate)
                    } else {
                        EmptyLetterTile(letter: letter)
                    }
                }
            }
            .padding()
        }
    }
}

struct AlphabetLetterTile: View {
    let letter: String
    let rewards: [String]
    let animate: Bool
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(AppTheme.primaryColor)
                    .frame(width: 60, height: 60)
                
                Text(letter)
                    .font(AppTheme.roundedFont(size: 26, weight: .bold))
                    .foregroundColor(.white)
                
                // Reward indicator
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                    
                    Text(rewards.first ?? "⭐️")
                        .font(.system(size: 14))
                }
                .offset(x: 20, y: -20)
            }
            .scaleEffect(scale)
            .onAppear {
                if animate {
                    withAnimation(Animation.spring().delay(Double.random(in: 0...0.3))) {
                        scale = 1.0
                    }
                }
            }
            .onChange(of: animate) { _, newValue in
                if !newValue {
                    scale = 0.8
                } else {
                    withAnimation(Animation.spring().delay(Double.random(in: 0...0.3))) {
                        scale = 1.0
                    }
                }
            }
            
            Text("\(rewards.count)")
                .font(AppTheme.roundedFont(size: 12, weight: .bold))
                .foregroundColor(AppTheme.secondaryColor)
        }
    }
}

struct EmptyLetterTile: View {
    let letter: String
    
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Text(letter)
                    .font(AppTheme.roundedFont(size: 26, weight: .bold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            
            Text("0")
                .font(AppTheme.roundedFont(size: 12))
                .foregroundColor(.gray.opacity(0.5))
        }
    }
}

struct LetterPerformanceCell: View {
    let performance: LetterPerformance
    
    var body: some View {
        VStack {
            Text(performance.letter)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.primary)
            
            if performance.attempts > 0 {
                Text("\(Int(performance.averageScore))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ColorForScore(performance.averageScore))
                
                Text("\(performance.attempts) tries")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("Not practiced")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 90)
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(performance.attempts > 0
                      ? Color(.secondarySystemBackground)
                      : Color(.tertiarySystemBackground))
        )
    }
    
    func ColorForScore(_ score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .orange }
        else { return .red }
    }
}

struct ProgressBarSegments: View {
    let score: Double
    
    var body: some View {
        ForEach(0..<10, id: \.self) { i in
            // simplifies conditional logic
            let isFilled = Double(i) * 10 <= score
            let fillColor = isFilled ? progressColor(score) : Color.gray.opacity(0.3)
            
            RoundedRectangle(cornerRadius: 2)
                .fill(fillColor)
                .frame(height: 10)
                .frame(maxWidth: .infinity)
        }
    }
}

struct MainDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedView: DashboardScreen = .home
    @State private var selectedSidebarItem: SidebarItem = .home

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                SidebarView(selectedView: $selectedView)
                    .frame(width: 80)
                    .background(AppTheme.adaptiveCardBackgroundColor(preferences: authManager.currentUser?.preferences))

                Divider()
                    .background(Color.gray.opacity(0.2))

                contentView(for: selectedView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.adaptiveBackgroundColor(preferences: authManager.currentUser?.preferences))
            }
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private func contentView(for view: DashboardScreen) -> some View {
        switch view {
        case .home: HomeDashboardView(selectedSidebarItem: $selectedSidebarItem)
        case .allLetters: AllLettersView()
        case .focusMode: FocusModeView()
        case .rewards: MyRewardsView()
        case .rewardsDetail: RewardsDashboardView()
        case .teacher: TeacherDashboardView()
        }
    }
}

struct AllLettersView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedLetterIndex: Int = 0
    @State private var showPath: Bool = false
    @State private var showEmojiPicker: Bool = false
    @State private var selectedSidebarItem: SidebarItem = .home

    private let letters = (65...90).map { String(UnicodeScalar($0)) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Practice All Letters")
                            .font(.largeTitle.bold())

                        Text("Tap a letter below to start tracing.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if let emoji = authManager.currentUser?.preferences.characterEmoji {
                        Button(action: {
                            showEmojiPicker = true
                        }) {
                            ExpressiveCharacter(
                                emoji: emoji,
                                expression: .happy
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tap to change character")
                        .sheet(isPresented: $showEmojiPicker) {
                            EmojiPickerSheet(
                                selectedEmoji: emoji,
                                onSelect: { newEmoji in
                                    authManager.currentUser?.preferences.characterEmoji = newEmoji
                                    authManager.saveUsers()
                                    showEmojiPicker = false
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(letters.indices, id: \.self) { index in
                            let letter = letters[index]
                            Button(action: {
                                selectedLetterIndex = index
                            }) {
                                VStack(spacing: 4) {
                                    Text(letter)
                                        .font(.title2)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(selectedLetterIndex == index ? AppTheme.primaryColor : Color.gray.opacity(0.2)))
                                        .foregroundColor(selectedLetterIndex == index ? .white : .primary)

                                    if let performance = authManager.currentPerformance,
                                       let score = performance.letterPerformances.first(where: { $0.letter == letter })?.averageScore {
                                        
                                        Text("\(Int(score))%")
                                            .font(.caption2)
                                            .foregroundColor(progressColor(score))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 25)
                        .fill(AppTheme.adaptiveCardBackgroundColor(preferences: authManager.currentUser?.preferences))
                        .shadow(radius: 4)
                        .frame(height: geo.size.height * 0.65)
                        .overlay {
                            TracingAppView(letter: letters[selectedLetterIndex], showPath: $showPath)
                                .padding()
                        }
                }
                .padding(.horizontal)

                Toggle("Show Path", isOn: $showPath)
                    .padding(.horizontal)
                    .toggleStyle(SwitchToggleStyle(tint: AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences)))

                Spacer(minLength: 30)
            }
            .padding(.top)
            .padding(.bottom, 40)
            .background(AppTheme.adaptiveBackgroundColor(preferences: authManager.currentUser?.preferences))
        }
    }
}

enum DashboardScreen {
    case home, allLetters, focusMode, rewards, rewardsDetail, teacher
}

struct SidebarView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var selectedView: DashboardScreen

    var body: some View {
        VStack(spacing: 24) {
            if let emoji = authManager.currentUser?.preferences.characterEmoji {
                Text(emoji)
                    .font(.system(size: 44))
                    .padding(.top, 30)
            }

            sidebarButton(.home, icon: "house")
            sidebarButton(.allLetters, icon: "abc")
            sidebarButton(.focusMode, icon: "scope")
            sidebarButton(.rewards, icon: "gift.fill")
            
            if authManager.currentUser?.role == .teacher {
                sidebarButton(.teacher, icon: "person.2.fill")
            }

            Spacer()
        }
        .padding(.vertical)
    }

    private func sidebarButton(_ view: DashboardScreen, icon: String) -> some View {
        Button {
            selectedView = view
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title(for: view))
                    .font(.caption2)
            }
            .foregroundColor(.primary)
            .padding(6)
            .frame(width: 60)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func title(for screen: DashboardScreen) -> String {
        switch screen {
        case .home: return "Home"
        case .allLetters: return "All"
        case .focusMode: return "Focus"
        case .rewards: return "Rewards"
        case .rewardsDetail: return "Details"
        case .teacher: return "Teacher"
        }
    }
}


// w celebration, theme fixes and child friendly style
struct HomeDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var selectedSidebarItem: SidebarItem
    @State private var characterMessage = ""
    @State private var dailyChallengeLetters: [String] = []
    @State private var completedChallengeLetters: [String] = []
    @State private var showSettings = false
    @State private var showTestSheet = false
    @State private var showCelebration = false
    @State private var showAnimation = false

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1), Color.pink.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // header w character
                        HStack(alignment: .top) {
                            Button {
                                let newEmoji = AppTheme.happyCharacters.randomElement() ?? "🦊"
                                authManager.currentUser?.preferences.characterEmoji = newEmoji
                                characterMessage = characterQuotes.randomElement() ?? ""
                                showAnimation.toggle()
                                authManager.saveUsers()
                            } label: {
                                Text(authManager.currentUser?.preferences.characterEmoji ?? "🦊")
                                    .font(.system(size: 60))
                                    .scaleEffect(showAnimation ? 1.2 : 1.0)
                                    .animation(.spring(), value: showAnimation)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Welcome back,")
                                    .font(.title3)
                                    .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                                Text(authManager.currentUser?.fullName ?? "Student")
                                    .font(.largeTitle.bold())
                                    .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: prefs))
                                if !characterMessage.isEmpty {
                                    Text("“\(characterMessage)”")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                                }
                            }

                            Spacer()

                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: prefs))
                            }
                            .sheet(isPresented: $showSettings) {
                                if let user = authManager.currentUser {
                                    AccessibilitySettingsView(currentPreferences: user.preferences)
                                        .environmentObject(authManager)
                                }
                            }
                        }

                        // recent practice
                        if let perf = lastLetterPracticed {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("📝 Last Practiced Letter: \(perf.letter)")
                                        .font(.headline)
                                    Text("Score: \(Int(perf.averageScore))%")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                                    Button("Continue") {
                                        selectedSidebarItem = .allLetters
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }

                        // streak ring (inspired by duolingo)
                        if let streak = streak {
                            SectionCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("🔥 Current Streak")
                                        .font(.headline)
                                    HStack(spacing: 20) {
                                        ZStack {
                                            Circle()
                                                .stroke(lineWidth: 10)
                                                .opacity(0.2)
                                                .foregroundColor(.orange)

                                            Circle()
                                                .trim(from: 0.0, to: min(Double(streak % 7) / 7.0, 1.0))
                                                .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                                .foregroundColor(.orange)
                                                .rotationEffect(.degrees(-90))
                                                .animation(.easeOut(duration: 0.5), value: streak)

                                            Text("\(streak)d")
                                                .font(.headline)
                                                .foregroundColor(.orange)
                                        }
                                        .frame(width: 70, height: 70)

                                        Text("You've practiced \(streak) day\(streak == 1 ? "" : "s") in a row!")
                                            .font(.subheadline)
                                            .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                                    }
                                }
                            }
                        }

                        // daily challenge
                        // random 3 letters didplayed to do
                        SectionCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("🎯 Today’s Challenge")
                                    .font(.headline)

                                HStack {
                                    ForEach(dailyChallengeLetters, id: \.self) { letter in
                                        Text(letter)
                                            .font(.title2.bold())
                                            .padding(10)
                                            .background(
                                                completedChallengeLetters.contains(letter) ?
                                                Color.green.opacity(0.3) :
                                                AppTheme.primaryColor.opacity(0.1)
                                            )
                                            .cornerRadius(10)
                                    }
                                }

                                let completed = dailyChallengeLetters.filter { completedChallengeLetters.contains($0) }.count
                                Text("\(completed)/\(dailyChallengeLetters.count) Complete")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))

                                Button("Do Today's Challenge") {
                                    showTestSheet = true
                                }
                                .buttonStyle(.borderedProminent)

                                if completed == dailyChallengeLetters.count {
                                    // only displays celebration if button clicked to view it (reduces there being too much visuals on screen)
                                    Button("🎉 View Congratulations") {
                                        showCelebration = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        Spacer(minLength: 60)
                    }
                    .padding()
                }
                .sheet(isPresented: $showTestSheet) {
                    WeakLetterTestView(lettersToTest: dailyChallengeLetters, isPresented: $showTestSheet)
                        .environmentObject(authManager)
                }

                // celebration overlay
                if showCelebration {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 20) {
                            Text(authManager.currentUser?.preferences.characterEmoji ?? "🦊")
                            // uses character 4 consistent fun
                                .font(.system(size: 60))
                            Text("Well done on completing the daily challenge, you're absolutely super! 🌟")
                                .multilineTextAlignment(.center)
                                .font(.title2.bold())
                                .padding()
                                .background(Color.white.opacity(0.95))
                                .cornerRadius(16)
                                .foregroundColor(.primary)
                            Button("Yay!") {
                                showCelebration = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
                        .shadow(radius: 10)
                        .padding()
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Home")
        }
        .navigationViewStyle(.stack)
        .onAppear {
            characterMessage = characterQuotes.randomElement() ?? ""
            generateDailyChallenge()
        }
    }

    private func SectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            content()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 3)
    }

    private var prefs: UserPreferences? {
        authManager.currentUser?.preferences
    }

    private var characterQuotes: [String] {
        [
            // random nice messages 'being said by' characters
            "You're doing amazing!",
            "Keep it up!",
            "Let’s trace something new!",
            "Foxy is proud of you!",
            "Can you finish your challenge today?"
        ]
    }

    private var lastLetterPracticed: LetterPerformance? {
        authManager.currentPerformance?.letterPerformances
            .sorted(by: { $0.lastPracticed > $1.lastPracticed })
            .first
    }

    private var streak: Int? {
        authManager.currentPerformance?.consecutiveDayStreak
    }

    private func generateDailyChallenge() {
        if dailyChallengeLetters.isEmpty {
            dailyChallengeLetters = Array((65...90).compactMap { UnicodeScalar($0).map { String($0) } }.shuffled().prefix(3))
        }

        if let performances = authManager.currentPerformance?.letterPerformances {
            completedChallengeLetters = performances
                .filter { dailyChallengeLetters.contains($0.letter) && $0.attempts > 0 }
                .map { $0.letter }
        }
    }
}

struct CharacterMessageBubble: View {
    let character: String
    let expression: ExpressiveCharacter.Expression
    let message: String
    @State private var animateBubble = false
    
    var body: some View {
        HStack(spacing: 5) {
            // Character
            ExpressiveCharacter(
                emoji: character,
                expression: expression
            )
            .frame(width:
                    80, height: 80)
            
            // Speech bubble
            VStack(alignment: .leading, spacing: 5) {
                Text(message)
                    .font(AppTheme.roundedFont(size: 16))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Tap for more tips")
                    .font(AppTheme.roundedFont(size: 12))
                    .foregroundColor(.secondary)
                    .opacity(animateBubble ? 0.6 : 1.0)
                    .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateBubble)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.1), radius: 4)
            )
            .overlay(
                // Speech bubble pointer
                Path { path in
                    path.move(to: CGPoint(x: -8, y: 25))
                    path.addLine(to: CGPoint(x: 0, y: 20))
                    path.addLine(to: CGPoint(x: 0, y: 30))
                    path.closeSubpath()
                }
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 1)
                .frame(width: 10, height: 40),
                alignment: .leading
            )
        }
        .padding(.horizontal)
        .onAppear {
            animateBubble = true
        }
    }
}

struct MyRewardsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedReward: (emoji: String, meaning: String)?
    @State private var showTooltip = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("🏆 My Rewards")
                        .font(.largeTitle.bold())
                        .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: prefs))
                        .padding(.top)
                    
                    // if none
                    if rewardsByLetter.isEmpty {
                        Text("You haven’t earned any rewards yet.\nStart practicing to collect some!")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    } else {
                        // displays full rewards list per letter
                        ForEach(rewardsByLetter.keys.sorted(), id: \.self) { letter in
                            if let rewards = rewardsByLetter[letter] {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("🔤 Letter \(letter)")
                                        .font(.headline)
                                        .foregroundColor(AppTheme.adaptiveTextColor(preferences: prefs))

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(rewards, id: \.self) { emoji in
                                                Button(action: {
                                                    selectedReward = (emoji, rewardMeanings[emoji] ?? "A special reward!")
                                                    showTooltip = true
                                                }) {
                                                    Text(emoji)
                                                        .font(.system(size: 40))
                                                        .padding(10)
                                                        .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs))
                                                        .cornerRadius(16)
                                                        .shadow(radius: 2)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding()
                                .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs).opacity(0.95))
                                .cornerRadius(20)
                                .shadow(Color: .black.opacity(0.05), radius: 4, x: 0, y: 3)
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }

            if showTooltip, let reward = selectedReward {
                Color.black.opacity(0.3).ignoresSafeArea()
                    .onTapGesture {
                        showTooltip = false
                    }

                VStack(spacing: 12) {
                    Text(reward.emoji)
                        .font(.system(size: 60))
                    Text(reward.meaning)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Got it!") {
                        showTooltip = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs))
                .cornerRadius(20)
                .shadow(radius: 10)
                .padding(30)
                .transition(.scale)
            }
        }
        .background(AppTheme.adaptiveBackgroundColor(preferences: prefs).ignoresSafeArea())
    }

    private var prefs: UserPreferences? {
        authManager.currentUser?.preferences
    }

    private var rewardsByLetter: [String: [String]] {
        guard let user = authManager.currentUser,
              let performance = authManager.currentPerformance else {
            return [:]
        }

        var dict: [String: [String]] = [:]
        for lp in performance.letterPerformances {
            if !lp.rewards.isEmpty {
                dict[lp.letter] = lp.rewards
            }
        }
        return dict
    }

    private var rewardMeanings: [String: String] {
        // for personal reference
        // if reward tapped on, will display reasoning though
        [
            "🎯": "First attempt on this letter!",
            "⭐️": "Great score (90%+)!",
            "🌟": "Amazing! (95%+)",
            "🏆": "Top score! (98%+)",
            "📈": "Big improvement!",
            "🎨": "You've mastered this letter!",
            "🔥": "Part of your streak!",
            "✏️": "Nice drawing!",
            "🖌️": "Awesome brush control!",
            "🎊": "Surprise bonus!",
            "🎭": "Very expressive!",
            "🎲": "Lucky bonus!"
        ]
    }
}

// Custom CharacterSelectionView with callback
struct CharacterSelectionView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedCharacter: String
    @State private var showSavedMessage = false
    
    let onSelect: (String) -> Void
    
    // initialise with current character (usually fox to start with)
    init(currentCharacter: String, onSelect: @escaping (String) -> Void) {
        _selectedCharacter = State(initialValue: currentCharacter)
        self.onSelect = onSelect
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppTheme.backgroundColor
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 25) {
                    // Title and description
                    VStack(spacing: 10) {
                        Text("Choose Your Helper Friend")
                            .font(AppTheme.roundedFont(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.primaryColor)
                            .multilineTextAlignment(.center)
                        
                        Text("Who do you want to help you learn letters?")
                            .font(AppTheme.roundedFont(size: 18))
                            .foregroundColor(.primary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    
                    // Current selection display
                    VStack(spacing: 15) {
                        ExpressiveCharacter(
                            emoji: selectedCharacter,
                            expression: .excited
                        )
                        .frame(height: 100)
                        
                        Text("Your helper friend will give you tips and celebrate your progress!")
                            .font(AppTheme.roundedFont(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                    
                    // Character grid
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80, maximum: 100))
                    ], spacing: 20) {
                        ForEach(AppTheme.happyCharacters, id: \.self) { character in
                            CharacterSelectionButton(
                                character: character,
                                isSelected: selectedCharacter == character,
                                onTap: {
                                    SoundManager.shared.playClick()
                                    selectedCharacter = character
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Save button
                    Button(action: saveSelection) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20))
                            Text("Save My Helper")
                                .font(AppTheme.roundedFont(size: 20, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(AppTheme.primaryColor)
                                .shadow(color: AppTheme.primaryColor.opacity(0.5), radius: 5, x: 0, y: 3)
                        )
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                }
                
                // Success message
                if showSavedMessage {
                    VStack {
                        Text("Saved! 🎉")
                            .font(AppTheme.roundedFont(size: 20, weight: .bold))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(Color.white)
                                    .shadow(radius: 5)
                            )
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .navigationBarTitle("", displayMode: .inline)
        }
    }
    
    private func saveSelection() {
        SoundManager.shared.playSuccess()
        onSelect(selectedCharacter)
        
        // Show saved message briefly
        withAnimation {
            showSavedMessage = true
        }
        
        // Hide message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSavedMessage = false
            }
            
            // Dismiss after another short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}

struct FocusModeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var weakestLetters: [LetterPerformance] = []
    @State private var showTest = false
    @State private var animateGradient = false
    @State private var sparkleOffset: CGFloat = -200
    @State private var animateBuddy = false

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    AppTheme.secondaryColor.opacity(0.4),
                    Color.white.opacity(0.3)
                ]),
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(Animation.linear(duration: 10).repeatForever(autoreverses: true), value: animateGradient)
            .onAppear {
                animateGradient = true
            }

            VStack {
                ForEach(0..<10, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 4...8))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: sparkleOffset + CGFloat(i * 60)
                        )
                        .blur(radius: 1)
                        .animation(Animation.linear(duration: Double.random(in: 6...10)).repeatForever(), value: sparkleOffset)
                }
            }
            .onAppear {
                sparkleOffset = UIScreen.main.bounds.height + 100
            }

            VStack(spacing: 15) {
                Spacer().frame(height: 40)

                if let emoji = authManager.currentUser?.preferences.characterEmoji {
                    HStack(spacing: 10) {
                        Text(emoji)
                            .font(.system(size: 60))
                            .scaleEffect(animateBuddy ? 1.1 : 1.0)
                            .animation(Animation.easeInOut(duration: 1).repeatForever(), value: animateBuddy)
                            .onAppear { animateBuddy = true }

                        Text("Let's beat these tricky letters!")
                            .font(.body.bold())
                            .padding(10)
                            .background(Color.white.opacity(0.9))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                            .shadow(radius: 2)
                    }
                }

                Text("🎯 Focus Mode")
                    .font(.largeTitle.bold())
                    .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: prefs))
                    .padding(.top, 5)

                if hasEnoughData {
                    focusModeReadyView
                } else {
                    focusModeNotReadyView
                }

                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showTest, onDismiss: refreshWeakestLetters) {
            WeakLetterTestView(
                lettersToTest: weakestLetters.map { $0.letter },
                isPresented: $showTest
            )
            .environmentObject(authManager)
        }
        .onAppear {
            refreshWeakestLetters()
        }
    }

    private var hasEnoughData: Bool {
        weakestLetters.count == 6
    }

    private var prefs: UserPreferences? {
        authManager.currentUser?.preferences
    }

    private func refreshWeakestLetters() {
        if let performance = authManager.currentPerformance {
            weakestLetters = authManager.getWeakestLetters(for: performance.id, count: 6)
        }
    }

    private var focusModeReadyView: some View {
        VStack(spacing: 10) {
            Text("Here are the letters you find most tricky:")
                .font(.headline)
                .foregroundColor(AppTheme.adaptiveTextColor(preferences: prefs))
                .padding(.top, 5)

            VStack(spacing: 8) {
                ForEach(weakestLetters) { perf in
                    HStack {
                        Text(perf.letter)
                            .font(.system(size: 34, weight: .bold))
                            .frame(width: 44)
                        Text("\(Int(perf.averageScore))%")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                }
            }

            Button("Start Test") {
                showTest = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 5)
        }
        .padding()
        .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs).opacity(0.95))
        .cornerRadius(20)
        .shadow(radius: 5)
        .padding(.horizontal)
    }

    private var focusModeNotReadyView: some View {
        VStack(spacing: 12) {
            Text("😕 Not enough practice yet!")
                .font(.headline)
                .foregroundColor(AppTheme.adaptiveTextColor(preferences: prefs))

            Text("You need to practice at least 6 letters before starting Focus Mode.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                .padding(.horizontal)
        }
        .padding()
        .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs).opacity(0.95))
        .cornerRadius(20)
        .shadow(radius: 5)
        .padding(.horizontal)
    }
}

// simple PDF view of one StudentPerformance:
struct ExportPDFView: View {
    let performance: StudentPerformance

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📘 Student Report")
                .font(.title.bold())

            Text("Name: \(performance.studentName)")
            Text("Average: \(Int(performance.overallAverage))%")
            Text("Streak: \(performance.consecutiveDayStreak) days")
            Text("Last Practice: \(performance.lastPracticeDate.formatted(date: .abbreviated, time: .omitted))")
            Divider()

            ForEach(performance.letterPerformances.sorted(by: { $0.letter < $1.letter })) { lp in
                HStack {
                    Text(lp.letter).bold().frame(width: 30)
                    Text("Avg: \(Int(lp.averageScore))%")
                    Spacer()
                    Text("×\(lp.attempts)")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
// graph stuff for teacher view
struct GraphicalInsightsView: View {
    @EnvironmentObject var authManager: AuthManager

    private var performance: StudentPerformance? {
        authManager.currentPerformance
    }

    private var prefs: UserPreferences? {
        authManager.currentUser?.preferences
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("📊 Insights")
                    .font(AppTheme.roundedFont(size: 28, weight: .bold))
                    .padding(.top)

                if let perf = performance {
                    // Letter Score Trends
                    VStack(alignment: .leading, spacing: 20) {
                        Text("📈 Letter Score Trends")
                            .font(AppTheme.roundedFont(size: 20, weight: .semibold))
                        Chart {
                            ForEach(perf.letterPerformances.sorted(by: { $0.letter < $1.letter })) { lp in
                                LineMark(
                                    x: .value("Letter", lp.letter),
                                    y: .value("Average", lp.averageScore)
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .frame(height: 200)
                    }
                    .padding()
                    .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs))
                    .cornerRadius(16)

                    // Mastery Breakdown
                    VStack(alignment: .leading, spacing: 20) {
                        Text("🎉 Mastery Breakdown")
                            .font(AppTheme.roundedFont(size: 20, weight: .semibold))
                        Chart {
                            BarMark(
                                x: .value("Mastered", "Mastered"),
                                y: .value("Count", perf.masteredLetters.count)
                            )
                            BarMark(
                                x: .value("Needs Work", "Needs Work"),
                                y: .value("Count", perf.lettersNeedingImprovement.count)
                            )
                        }
                        .frame(height: 180)
                    }
                    .padding()
                    .background(AppTheme.adaptiveCardBackgroundColor(preferences: prefs))
                    .cornerRadius(16)

                    // Export Buttons
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            let exportView = ExportPDFView(performance: perf)
                            let fileName = "\(perf.studentName)_Report"
                            Task {
                                await ExportHelper.exportViewAsPDF(exportView, fileName: fileName)
                            }
                        } label: {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            ExportHelper.exportCSV(perf)
                        } label: {
                            Label("Export CSV", systemImage: "doc.plaintext")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top)

                } else {
                    Text("No data available")
                        .font(.headline)
                        .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: prefs))
                        .padding()
                }
            }
            .padding()
        }
        .background(AppTheme.adaptiveBackgroundColor(preferences: prefs))
        .navigationTitle("Insights")
    }
}


struct LetterDrilldownView: View {
    let letter: String
    let classPerformance: [StudentPerformance]
    
    @Environment(\.dismiss) var dismiss

    private var allScores: [Double] {
        classPerformance.flatMap {
            $0.letterPerformances.first(where: { $0.letter == letter })?.scores ?? []
        }
    }

    private var totalAttempts: Int {
        classPerformance.reduce(0) { result, student in
            result + (student.letterPerformances.first(where: { $0.letter == letter })?.attempts ?? 0)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("📖 Letter: \(letter)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Total Attempts: \(totalAttempts)")
                    .font(.headline)
                    .foregroundColor(.secondary)

                if allScores.count > 1 {
                    Chart {
                        ForEach(Array(allScores.enumerated()), id: \.offset) { index, score in
                            LineMark(
                                x: .value("Attempt", index + 1),
                                y: .value("Score", score)
                            )
                        }
                    }
                    .frame(height: 220)
                    .padding(.horizontal)
                } else {
                    Text("Not enough data for a trend chart")
                        .foregroundColor(.gray)
                        .padding()
                }

                Spacer()
            }
            .padding()
            .background(AppTheme.adaptiveBackgroundColor(preferences: nil))
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// for insights based on teacher selected timeframe
enum TimeFrame: String, CaseIterable {
    case week, month, allTime

    var label: String {
        switch self {
            // emojis included w stuff for better clarity but mostly for aesthetics
        case .week: return "📅 Week"
        case .month: return "🗓️ Month"
        case .allTime: return "⏳ All Time"
        }
    }
}

// teachers view
struct TeacherDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedStudent: User? = nil
    @State private var selectedTab = 0
    @State private var selectedLetter: String? = nil
    @State private var searchText: String = ""
    @State private var filterByStreak = false
    @State private var filterByLowScore = false

    var preferences: UserPreferences? {
        authManager.currentUser?.preferences
    }

    var filteredStudents: [User] {
        var students = authManager.students

        if filterByStreak {
            students = students.filter {
                (authManager.getStudentPerformanceFromSQLite(for: $0.id)?.consecutiveDayStreak ?? 0) >= 3
            }
        }

        if filterByLowScore {
            students = students.filter {
                (authManager.getStudentPerformanceFromSQLite(for: $0.id)?.overallAverage ?? 100) < 70
            }
        }

        if !searchText.isEmpty {
            students = students.filter {
                $0.fullName.lowercased().contains(searchText.lowercased()) ||
                $0.username.lowercased().contains(searchText.lowercased())
            }
        }

        return students.sorted { $0.username.lowercased() < $1.username.lowercased() }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Picker("Mode", selection: $selectedTab) {
                    Text("📋 Overview").tag(0)
                    Text("📤 Export").tag(1)
                    Text("📈 Trends").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                if selectedTab == 0 {
                    overviewPage
                } else if selectedTab == 1 {
                    exportPage
                } else {
                    TrendsAnalyticsView()
                }
            }
            .padding()
            .background(AppTheme.adaptiveBackgroundColor(preferences: preferences))
            .navigationTitle("👩‍🏫 Teacher Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .sheet(item: $selectedStudent) { student in
                StudentDetailView(student: student)
            }
        }
    }

    var overviewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("🧑‍🎓 Student Overview")
                .font(AppTheme.roundedFont(size: 28, weight: .bold))
                .foregroundColor(AppTheme.primaryColor)

            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search students...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)

            Toggle("🎯 Show students with streak ≥ 3", isOn: $filterByStreak)
                .padding(.horizontal)

            Toggle("⚠️ Show students with avg < 70%", isOn: $filterByLowScore)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredStudents) { student in
                        if let performance = authManager.getStudentPerformanceFromSQLite(for: student.id) {
                            Button(action: {
                                selectedStudent = student
                            }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(student.fullName.isEmpty ? student.username : student.fullName)
                                            .font(AppTheme.roundedFont(size: 18, weight: .semibold))
                                        Spacer()
                                        Text("Avg: \(Int(performance.overallAverage))%")
                                            .foregroundColor(.gray)
                                    }

                                    ProgressView(value: performance.overallAverage / 100)
                                        .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.primaryColor))
                                }
                                .padding()
                                .background(AppTheme.adaptiveCardBackgroundColor(preferences: preferences))
                                .cornerRadius(12)
                                .shadow(radius: 2)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.bottom)
            }
        }
    }

    var exportPage: some View {
        VStack(spacing: 24) {
            Text("📤 Export Student Data")
                .font(AppTheme.roundedFont(size: 24, weight: .bold))
                .foregroundColor(AppTheme.accentColor)

            Button(action: {
                Task {
                    await ExportHelper.exportAllStudentsPDF(using: authManager)
                }
            }) {
                Label("Export All as PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(.borderedProminent)

            Button(action: {
                Task {
                    await ExportHelper.exportAllStudentsCSV(using: authManager)
                }
            }) {
                Label("Export All as CSV", systemImage: "tablecells")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }
}

struct TrendsAnalyticsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedLetter: String?
    @State private var exportImage: Image?
    @State private var showExportSheet = false
    @State private var selectedRange: TimeRange = .allTime
    
// using the enum i had for the different timescales
    enum TimeRange: String, CaseIterable {
        case week, month, allTime
    }

    var classPerformance: [StudentPerformance] {
        authManager.students.compactMap {
            authManager.getStudentPerformanceFromSQLite(for: $0.id)
        }
    }

    var letterAverages: [(letter: String, average: Double)] {
        let letters = (65...90).compactMap { UnicodeScalar($0).map { String($0) } } // A-Z
        return letters.map { letter in
            let scores = classPerformance.compactMap {
                $0.letterPerformances.first(where: { $0.letter == letter })?.averageScore
            }
            let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            return (letter, avg)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("📊 Class Letter Trends")
                    .font(AppTheme.roundedFont(size: 26, weight: .bold))
                    .padding(.top)

                Picker("Time Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue.capitalized)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Chart(letterAverages, id: \.letter) { item in
                    BarMark(
                        x: .value("Letter", item.letter),
                        y: .value("Average", item.average)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(Int(item.average))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 260)
                .background(AppTheme.adaptiveCardBackgroundColor(preferences: authManager.currentUser?.preferences))
                .cornerRadius(20)
                .shadow(radius: 4)
                .padding()

                if let exportImage = exportImage {
                    exportImage
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .padding(.top)
                        .transition(.scale)
                }

                Button("📤 Export Snapshot") {
                    captureChartSnapshot()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Trends")
        .sheet(item: $selectedLetter) { letter in
            LetterDrilldownView(letter: letter, classPerformance: classPerformance)
        }
    }

    private func captureChartSnapshot() {
        let renderer = ImageRenderer(content:
            Chart(letterAverages, id: \.letter) { item in
                BarMark(x: .value("Letter", item.letter), y: .value("Average", item.average))
                    .foregroundStyle(.blue)
            }
            .frame(width: 360, height: 240)
        )

        if let uiImage = renderer.uiImage {
            exportImage = Image(uiImage: uiImage)
            showExportSheet = true
        }
    }
}
// per student details
struct StudentDetailView: View {
    let student: User
    @EnvironmentObject var authManager: AuthManager

    private var performance: StudentPerformance? {
        authManager.getStudentPerformanceFromSQLite(for: student.id)
    }

    private var sortedLetterPerformances: [LetterPerformance] {
        guard let performances = performance?.letterPerformances else { return [] }
        return performances.sorted { $0.letter < $1.letter }
    }

    private var weakLetters: [LetterPerformance] {
        authManager.getWeakestLetters(for: student.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let performance = performance {
                    studentOverviewCard(performance: performance)
                    statsOverview(performance: performance)
                    quickInsights(performance: performance)
                    letterPerformanceGrid()
                    weakLettersSection()
                } else {
                    Text("No performance data available")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(AppTheme.adaptiveSecondaryTextColor(preferences: authManager.currentUser?.preferences))
                        .padding()
                }
            }
            .padding()
        }
        .background(AppTheme.adaptiveBackgroundColor(preferences: authManager.currentUser?.preferences))
        .navigationTitle(student.fullName.isEmpty ? student.username : student.fullName)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(student.fullName.isEmpty ? student.username : student.fullName)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))
            }
        }
    }

    private func studentOverviewCard(performance: StudentPerformance) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 5) {
                    Text(student.fullName.isEmpty ? student.username : student.fullName)
                        .font(.system(size: 22, weight: .regular, design: .rounded))
                        .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))
                        .fontWeight(.bold)

                    if !student.fullName.isEmpty {
                        Text("@\(student.username)")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(AppTheme.adaptiveSecondaryColor(preferences: authManager.currentUser?.preferences))
                    }
                }

                Spacer()

                ProgressCircle(progress: performance.overallAverage)
                    .frame(width: 60, height: 60)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func statsOverview(performance: StudentPerformance) -> some View {
        HStack {
            StatView(value: "\(performance.letterPerformances.reduce(0) { $0 + $1.attempts })",
                    label: "Total Attempts")
            Divider()
            StatView(value: "\(performance.letterPerformances.filter { $0.attempts > 0 }.count)",
                    label: "Letters Practiced")
            Divider()
            StatView(value: "\(performance.letterPerformances.filter { $0.averageScore >= 80 }.count)",
                    label: "Mastered")
        }
        .frame(height: 80)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func quickInsights(performance: StudentPerformance) -> some View {
        let best = performance.letterPerformances.max(by: { $0.averageScore < $1.averageScore })
        let mostImproved = performance.letterPerformances.max(by: { ($0.averageScore - ($0.previousAverage ?? 0)) < ($1.averageScore - ($1.previousAverage ?? 0)) })

        return VStack(alignment: .leading, spacing: 12) {
            Text("Highlights")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))

            HStack(spacing: 16) {
                if let best = best {
                    HighlightBox(title: "Best Letter", value: best.letter, Color: AppTheme.funGreen)
                }
                if let mostImproved = mostImproved {
                    HighlightBox(title: "Most Improved", value: mostImproved.letter, Color: AppTheme.funBlue)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func letterPerformanceGrid() -> some View {
        VStack(alignment: .leading) {
            Text("Letter Performance")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 15) {
                ForEach(sortedLetterPerformances) { perf in
                    LetterPerformanceCell(performance: perf)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    private func weakLettersSection() -> some View {
        VStack(alignment: .leading) {
            Text("Areas to Improve")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))

            if weakLetters.isEmpty {
                Text("No weak letters identified")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppTheme.adaptiveSecondaryColor(preferences: authManager.currentUser?.preferences))
                    .padding()
            } else {
                ForEach(weakLetters) { letter in
                    HStack {
                        Text(letter.letter)
                            .font(.system(size: 24, design: .rounded))
                            .fontWeight(.bold)
                            .frame(width: 50, height: 50)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)

                        VStack(alignment: .leading) {
                            Text("Score: \(Int(letter.averageScore))%")
                                .font(.system(size: 16, design: .rounded))

                            Text("Attempted \(letter.attempts) times")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(AppTheme.adaptiveSecondaryColor(preferences: authManager.currentUser?.preferences))
                        }

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text("Last practiced:")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(AppTheme.adaptiveSecondaryColor(preferences: authManager.currentUser?.preferences))

                            Text(letter.lastPracticed.formatted(date: .numeric, time: .omitted))
                                .font(.system(size: 14, design: .rounded))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(radius: 1)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct HighlightBox: View {
    let title: String
    let value: String
    let Color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(SwiftUICore.Color(.systemGray6))
        .cornerRadius(10)
    }
}

// settings stuff
// makes things customisable eg sound, dark mode etc
struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showAccessibilitySettings = false
    @State private var showCharacterSelection = false
    @State private var showSQLiteScores = false
    @State private var selectedCharacter: String
    
    init() {
        _selectedCharacter = State(initialValue: "🦊") // Default character
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Appearance")
                            .font(.system(size:18, design: .rounded))

                            .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))) {
                    Button(action: {
                        showAccessibilitySettings = true
                    }) {
                        HStack {
                            Image(systemName: "textformat.size")
                                .foregroundColor(AppTheme.primaryColor)
                            Text("Display & Accessibility")
                                .font(.system(size: 16, design: .rounded))

                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Button(action: {
                        showCharacterSelection = true
                    }) {
                        HStack {
                            Text(selectedCharacter)
                                .font(.system(size: 24, design: .rounded))

                            Text("Change Helper Friend")
                                .font(.system(size: 16, design: .rounded))

                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("Data")                            .font(.system(size: 18, design: .rounded))

                            .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences))) {
                    Button(action: {
                        showSQLiteScores = true
                    }) {
                        HStack {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundColor(AppTheme.primaryColor)
                            Text("View All Scores")
                                .font(.system(size: 16, design: .rounded))

                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        authManager.logout()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text("Log Out")
                                .foregroundColor(.red)
                                .font(.system(size: 16, design: .rounded))

                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle(Text("Settings")
                                .font(.system(size: 20, design: .rounded))

                                .foregroundColor(AppTheme.adaptivePrimaryColor(preferences: authManager.currentUser?.preferences)))
            .onAppear {
                if let user = authManager.currentUser {
                    selectedCharacter = user.preferences.characterEmoji
                }
            }
            .sheet(isPresented: $showAccessibilitySettings) {
                if let user = authManager.currentUser {
                    AccessibilitySettingsView(currentPreferences: user.preferences)
                        .environmentObject(authManager)
                }
            }
            .sheet(isPresented: $showCharacterSelection) {
                CharacterSelectionView(currentCharacter: selectedCharacter) { newCharacter in
                    withAnimation {
                        selectedCharacter = newCharacter
                    }
                    
                    if let user = authManager.currentUser {
                        var updatedPreferences = user.preferences
                        updatedPreferences.characterEmoji = newCharacter
                        authManager.updateUserPreferences(for: user.id, preferences: updatedPreferences)
                    }
                }
                .environmentObject(authManager)
            }
            .sheet(isPresented: $showSQLiteScores) {
                SQLiteScoresView()
                    .environmentObject(authManager)
            }
        }
    }
}

struct TracingCanvasView: View {
    @EnvironmentObject var authManager: AuthManager
    let letter: String
    @Binding var userDrawnPath: Path
    @Binding var userDrawnSegments: [Path]
    let showNumberedGuide: Bool
    let showArrows: Bool
    let showPath: Bool
    let isTrySampleMode: Bool
    @Binding var animateStroke: Bool
    @Binding var strokeProgress: CGFloat
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(Color.gray.opacity(0.1))
                .border(Color.black, width: 1)
            
            //  reference path
            if isTrySampleMode {
                TracingAnimatedPathView(letter: letter, progress: strokeProgress)
                    .stroke(Color.blue, lineWidth: 4)
                    .opacity(0.7)
            } else if showPath {
                TracingPathView(letter: letter)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [5, 5]))
                    .opacity(0.6)
            }
            
            // Users drawn segments
            ForEach(0..<userDrawnSegments.count, id: \.self) { index in
                userDrawnSegments[index]
                    .stroke(Color.green, lineWidth: 4)
                    .opacity(0.7)
            }
            
            // Current drawing path
            userDrawnPath
                .stroke(Color.green, lineWidth: 4)
                .opacity(0.7)
            
            // Guides
            if showNumberedGuide && !isTrySampleMode {
                NumberedPathGuideView(letter: letter)
                    .font(.system(size: 16, design: .rounded))

                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
            }
            if showArrows && !isTrySampleMode {
                DirectionalArrowsView(letter: letter)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
            }
        }
    }
}

struct TracingControlsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var currentLetterIndex: Int
    let letters: [String]
    @Binding var showNumberedGuide: Bool
    @Binding var showArrows: Bool
    @Binding var showPath: Bool
    @Binding var isTrySampleMode: Bool
    @Binding var animationSpeed: Double
    let onReset: () -> Void
    let onToggleSample: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            // Toggle controls
            HStack {
                Toggle("Show Numbers", isOn: $showNumberedGuide)
                    .frame(width: 150)
                    .disabled(isTrySampleMode)
                    .font(.system(size: 16, design: .rounded))

                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
                
                Toggle("Show Arrows", isOn: $showArrows)
                    .frame(width: 150)
                    .disabled(isTrySampleMode)
                    .font(.system(size: 16, design: .rounded))

                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
            }
            
            HStack {
                Toggle("Show Path", isOn: $showPath)
                    .frame(width: 150)
                    .disabled(isTrySampleMode)
                    .font(.system(size: 16, design: .rounded))

                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
                
                if isTrySampleMode {
                    HStack {
                        Text("Speed:")
                            .font(.system(size: 16, design: .rounded))

                            .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
                        
                        Slider(value: $animationSpeed, in: 0.5...2.0, step: 0.25)
                            .frame(width: 120)
                    }
                    .frame(width: 200)
                }
            }
            
            // Action buttons
            HStack(spacing: 15) {
                Button("Reset") { onReset() }
                    .padding()
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
                    .disabled(isTrySampleMode)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
                
                Button(isTrySampleMode ? "Stop Demo" : "Try Sample") { onToggleSample() }
                    .padding()
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
                
                Button("Previous") {
                    if currentLetterIndex > 0 {
                        currentLetterIndex -= 1
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
                .disabled(currentLetterIndex == 0 || isTrySampleMode)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
                
                Button("Next") {
                    if currentLetterIndex < letters.count - 1 {
                        currentLetterIndex += 1
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)
                .disabled(currentLetterIndex == letters.count - 1 || isTrySampleMode)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(AppTheme.adaptiveTextColor(preferences: authManager.currentUser?.preferences))
            }
        }
    }
}

struct TracingFeedbackView: View {
    @EnvironmentObject var authManager: AuthManager
    let score: Double
    
    var body: some View {
        VStack {
            Text("Accuracy: \(Int(score))%")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(getFeedbackColor(score: score))
            
            Text(getFeedbackMessage(score: score))
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(getFeedbackColor(score: score))
                .padding(.top, 5)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private func getFeedbackColor(score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .orange }
        else { return .red }
    }
    
    private func getFeedbackMessage(score: Double) -> String {
        if score >= 85 { return "Excellent! Perfect tracing!" }
        else if score >= 70 { return "Good job! Keep practicing!" }
        else if score >= 50 { return "Nice try! Follow the guides carefully." }
        else { return "Try again! Follow the numbered guides." }
    }
}

struct WeakLetterTestView: View {
    let lettersToTest: [String]
    @Binding var isPresented: Bool

    @State private var currentIndex = 0
    @State private var showPath = false
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 16) {
            TracingAppView(
                letter: lettersToTest[currentIndex],
                showPath: $showPath,
                practiceLetters: lettersToTest
            )
            .padding(.horizontal)

            Spacer()

            HStack(spacing: 20) {
                if currentIndex > 0 {
                    Button(action: {
                        currentIndex -= 1
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }

                Spacer()

                if currentIndex < lettersToTest.count - 1 {
                    Button(action: {
                        currentIndex += 1
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                    }
                } else {
                    Button("Finish") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
        .overlay(masteredCelebrationOverlay)
    }

    private var masteredCelebrationOverlay: some View {
        Group {
            if let perf = authManager.currentPerformance?.letterPerformances.first(where: {
                $0.letter == lettersToTest[currentIndex] && $0.isMastered
            }) {
                GeometryReader { geo in
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()

                        VStack(spacing: 20) {
                            Text(authManager.currentUser?.preferences.characterEmoji ?? "🦊")
                                .font(.system(size: 60))

                            Text("Congratulations on mastering \(perf.letter)!")
                                .multilineTextAlignment(.center)
                                .font(.title3.bold())
                                .padding()
                                .foregroundColor(.primary)
                                .background(Color.white.opacity(0.95))
                                .cornerRadius(16)

                            Button("Continue") {
                                // Dismiss overlay by changing index or closing view
                                if currentIndex < lettersToTest.count - 1 {
                                    currentIndex += 1
                                } else {
                                    isPresented = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
                        .shadow(radius: 10)
                        .padding()
                        .frame(maxWidth: geo.size.width * 0.85)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }
}

struct SegmentPathView: Shape {
    var points: [CGPoint]
    var progress: CGFloat // 0.0 to 1.0
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        // Return empty path if no points
        guard !points.isEmpty else { return Path() }
        
        var path = Path()
        
        // Move to the first point
        path.move(to: points[0])
        
        // If there's only one point // progress is 0 return just the starting point
        if points.count == 1 || progress <= 0 {
            return path
        }
        
        // Calculate how many points to include based on progress
        let totalPoints = points.count
        let pointsToInclude = max(1, Int(ceil(CGFloat(totalPoints - 1) * progress)) + 1)
        
        // Add lines to each included point
        for i in 1..<min(pointsToInclude, totalPoints) {
            path.addLine(to: points[i])
        }
        
        if progress < 1.0 && pointsToInclude < totalPoints {
            let lastFullPointIndex = pointsToInclude - 1
            let nextPointIndex = lastFullPointIndex + 1
            
            let segmentProgress = CGFloat(totalPoints - 1) * progress - CGFloat(lastFullPointIndex)
            
            // Get the last full point and the next point
            let lastFullPoint = points[lastFullPointIndex]
            let nextPoint = points[nextPointIndex]
            
            // Calculate the partial point
            let partialPoint = CGPoint(
                x: lastFullPoint.x + (nextPoint.x - lastFullPoint.x) * segmentProgress,
                y: lastFullPoint.y + (nextPoint.y - lastFullPoint.y) * segmentProgress
            )
            
            // Add line to the partial point
            path.addLine(to: partialPoint)
        }
        
        return path
    }
}
    
// registration view
// inspired by most ios apps i use (hence code slightly borrowed)
struct RegisterView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var fullName = ""
    @State private var dateOfBirth = Date()
    @State private var registerError = false
    @State private var errorMessage = ""
    
    //  allowed date range
    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: 1950, month: 1, day: 1)
        let endDate = Date()
        return calendar.date(from: startComponents)!...endDate
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Account Information")) {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                }
                
                Section(header: Text("Personal Information")) {
                    TextField("Full Name", text: $fullName)
                    DatePicker("Date of Birth",
                               selection: $dateOfBirth,
                               in: dateRange, //  Limit applied here
                               displayedComponents: .date)
                }
                
                if registerError {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
                
                Section {
                    Button("Register") {
                        registerStudent()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("New Student")
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    func registerStudent() {
        // Validation
        if username.isEmpty || password.isEmpty {
            registerError = true
            errorMessage = "Username and password are required"
            return
        }
        
        if password != confirmPassword {
            registerError = true
            errorMessage = "Passwords do not match"
            return
        }
        
        if fullName.isEmpty {
            registerError = true
            errorMessage = "Please enter your name"
            return
        }
        
        if authManager.registerStudent(username: username, password: password, fullName: fullName, dateOfBirth: dateOfBirth) {
            presentationMode.wrappedValue.dismiss()
        } else {
            registerError = true
            errorMessage = "Username already exists"
        }
    }
}

struct LetterProgressGrid: View {
    let performances: [LetterPerformance]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Letter Performance")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 15) {
                ForEach(performances.sorted { $0.letter < $1.letter }) { perf in
                    VStack {
                        Text(perf.letter)
                            .font(.system(size: 30, weight: .bold))
                        
                        if perf.attempts > 0 {
                            Text("\(Int(perf.averageScore))%")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(perf.averageScore >= 80 ? .green :
                                                perf.averageScore >= 60 ? .orange : .red)
                            
                            Text("\(perf.attempts) tries")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Text("Not practiced")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 90)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(perf.attempts > 0 ?
                                  Color(.secondarySystemBackground) :
                                  Color(.tertiarySystemBackground))
                    )
                }
            }
        }
    }
}

struct WeakLettersSection: View {
    let letters: [LetterPerformance]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Areas to Improve")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 5)
            
            ForEach(letters.prefix(5)) { letter in
                HStack {
                    Text(letter.letter)
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 50, height: 50)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading) {
                        Text("Score: \(Int(letter.averageScore))%")
                            .font(.subheadline)
                        
                        Text("Attempted \(letter.attempts) times")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Last practiced:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(letter.lastPracticed.formatted(date: .numeric, time: .omitted))
                            .font(.caption)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 1)
            }
        }
    }
}

// character emojis! some ended up not being implemented because otherwise too many
struct EmojiPickerSheet: View {
    let selectedEmoji: String
    let onSelect: (String) -> Void

    private let emojis = ["🦊", "🐰", "🐶", "🐱", "🐼", "🦁", "🐻", "🐨", "🐯", "🐸", "🐷", "🐥"]

    let columns = [
        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Pick Your Character")
                    .font(.title2.bold())
                    .padding(.top)

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button(action: {
                            onSelect(emoji)
                        }) {
                            ZStack {
                                Circle()
                                    .fill(emoji == selectedEmoji ? AppTheme.primaryColor.opacity(0.3) : Color.white)
                                    .frame(width: 70, height: 70)
                                    .shadow(radius: 2)

                                Text(emoji)
                                    .font(.system(size: 40))
                                    .scaleEffect(emoji == selectedEmoji ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.3), value: emoji == selectedEmoji)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onSelect(selectedEmoji)
                    }
                }
            }
        }
    }
}
