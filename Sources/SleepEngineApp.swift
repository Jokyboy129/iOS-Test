import SwiftUI
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers
import CoreHaptics

struct HeartbeatProfile: Hashable, Codable {
	let name: String
	let bpm: Double
	let lubBase: Double
	let lubDrop: Double
	let lubDecay: Double
	let dubBase: Double
	let dubDrop: Double
	let dubDecay: Double
	let dubDelay: Double
	let subFreq: Double
	let subVol: Double
	let subDecay: Double
	let whooshVol: Double
	let noiseLpf: Double
}

struct TrackData: Codable, Identifiable {
	var id = UUID()
	var name: String
	var path: String
	var volume: Double
	var isAppleMusic: Bool
	var delayAfterMeditation: Bool
}

class ImportedTrack: Identifiable, ObservableObject {
	let id: UUID
	@Published var name: String
	@Published var volume: Double { didSet { updatePlayerVolume() } }
	@Published var delayAfterMeditation: Bool = false { didSet { updatePlayerVolume() } }

	var avPlayer: AVAudioPlayer?
	var enginePlayerNode: AVAudioPlayerNode?
	var audioFile: AVAudioFile?

	var isAppleMusic: Bool
	var path: String
	var masterVolume: Double = 1.0 { didSet { updatePlayerVolume() } }
	var dynamicVolumeMultiplier: Double = 1.0 { didSet { updatePlayerVolume() } }
	var meditationFadeMultiplier: Double = 1.0 { didSet { updatePlayerVolume() } }
	var postMeditationMultiplier: Double = 1.0 { didSet { updatePlayerVolume() } }

	private func updatePlayerVolume() {
		let specificMultiplier = delayAfterMeditation ? postMeditationMultiplier : meditationFadeMultiplier

		if avPlayer != nil {
			let avVol = Float(volume * masterVolume * dynamicVolumeMultiplier * specificMultiplier)
			avPlayer?.volume = avVol
		}

		if enginePlayerNode != nil {
			let engineVol = Float(volume * masterVolume * dynamicVolumeMultiplier * specificMultiplier)
			enginePlayerNode?.volume = engineVol
		}
	}

	init(id: UUID = UUID(), name: String, volume: Double, isAppleMusic: Bool, path: String, delayAfterMeditation: Bool = false) {
		self.id = id
		self.name = name
		self.volume = volume
		self.isAppleMusic = isAppleMusic
		self.path = path
		self.delayAfterMeditation = delayAfterMeditation
	}

	func scheduleNextLoop() {
		guard let pNode = enginePlayerNode, let file = audioFile else { return }
		pNode.scheduleFile(file, at: nil, completionHandler: {
			DispatchQueue.main.async { [weak self] in
				self?.scheduleNextLoop()
			}
		})
	}

	func play() {
		avPlayer?.play()
		enginePlayerNode?.play()
	}

	func pause() {
		avPlayer?.pause()
		enginePlayerNode?.pause()
	}

	func stop() {
		avPlayer?.stop()
		enginePlayerNode?.stop()
	}
}

struct AudioRenderState {
	var selectedProfileIndex: Int = 0
	var placementIndex: Int = 0
	var heartbeatVolume: Float = 0
	var faceBrushVolume: Float = 0
	var clockVolume: Float = 0
	var softClickVolume: Float = 0
	var brownVolume: Float = 0
	var whiteVolume: Float = 0
	var breathVolume: Float = 0
	var clickVolume: Float = 0
	var binauralVolume: Float = 0
	var binauralTypeIndex: Int = 0
	var panHeartIndex: Int = 0
	var panClockIndex: Int = 0
	var panBrownIndex: Int = 0
	var panWhiteIndex: Int = 0
	var panBreathIndex: Int = 0
	var panClickIndex: Int = 0
	var panSoftClickIndex: Int = 0
	var clockTypeIndex: Int = 0
	var clickPatternIndex: Int = 0
	var softClickBoostEnabled: Bool = false
	var syncClock: Bool = false
	var syncClick: Bool = true
	var enableSlowdown: Bool = false
	var targetBPM: Double = 40.0
	var slowdownMinutes: Double = 30.0
	var enableRSA: Bool = false
	var syncBreathing: Bool = false
	var useRealBreathing: Bool = true
	var isBreathing: Bool = false
	var manualBreathState: Int = 0
	var soundscapeMultiplier: Float = 1.0
	var isPlaying: Bool = false
	var enableIntimateMode: Bool = false
}

struct MeditationItem {
	var avPlayer: AVAudioPlayer?
	var audioFile: AVAudioFile?
	var duration: TimeInterval = 0
}

class AudioEngineManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
	private enum MorningAlarmPhase {
		case idle
		case waiting
		case soundscapeFadeIn
		case alarmCrossfade
		case ringing
	}

	let engine = AVAudioEngine()
	var sourceNode: AVAudioSourceNode?
	let reverbNode = AVAudioUnitReverb()
	let preReverbMixer = AVAudioMixerNode()
	let postReverbMixer = AVAudioMixerNode()
	let importedMixer = AVAudioMixerNode()
	let hspEqNode = AVAudioUnitEQ(numberOfBands: 1)
	let proximityEqNode = AVAudioUnitEQ(numberOfBands: 2)

	let breathingNode = AVAudioPlayerNode()
	let anchorNode = AVAudioPlayerNode()
	let meditationPlayerNode = AVAudioPlayerNode()

	var rainPlayerNode: AVAudioPlayerNode?
	var rainAudioFile: AVAudioFile?
	var organicHeartbeatPlayerNode: AVAudioPlayerNode?
	var organicHeartbeatAudioFile: AVAudioFile?
	var alarmPlayer: AVAudioPlayer?
	var exporterAlarmNode: AVAudioPlayerNode?
	var exporterAlarmFile: AVAudioFile?
	var silentBackgroundPlayer: AVAudioPlayer?
	var meditationItems: [MeditationItem] = []

	var hapticEngine: CHHapticEngine?

	@Published var isPlaying: Bool = false { didSet { syncRenderState() } }
	@Published var importedTracks: [ImportedTrack] = []

	var dynamicVolumeMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	var meditationFadeMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	var postMeditationMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	var morningFadeMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	var alarmFadeMultiplier: Double = 0.0 { didSet { updateVolumes() } }

	let profiles: [HeartbeatProfile] = [
		HeartbeatProfile(name: String(localized: "ASMR Blood Flow (60 BPM)"), bpm: 60, lubBase: 40, lubDrop: 15, lubDecay: 18, dubBase: 50, dubDrop: 20, dubDecay: 22, dubDelay: 0.30, subFreq: 35, subVol: 0.25, subDecay: 6, whooshVol: 0.50, noiseLpf: 450),
		HeartbeatProfile(name: String(localized: "Standard Resting Heart (72 BPM)"), bpm: 72, lubBase: 45, lubDrop: 10, lubDecay: 20, dubBase: 55, dubDrop: 15, dubDecay: 25, dubDelay: 0.28, subFreq: 30, subVol: 0.30, subDecay: 5, whooshVol: 0.30, noiseLpf: 500),
		HeartbeatProfile(name: String(localized: "Womb Simulation (55 BPM)"), bpm: 55, lubBase: 55, lubDrop: 20, lubDecay: 20, dubBase: 70, dubDrop: 25, dubDecay: 25, dubDelay: 0.35, subFreq: 35, subVol: 0.45, subDecay: 5, whooshVol: 0.60, noiseLpf: 650),
		HeartbeatProfile(name: String(localized: "Zen Meditation (50 BPM)"), bpm: 50, lubBase: 35, lubDrop: 25, lubDecay: 15, dubBase: 45, dubDrop: 30, dubDecay: 18, dubDelay: 0.32, subFreq: 30, subVol: 0.40, subDecay: 4, whooshVol: 0.12, noiseLpf: 150),
		HeartbeatProfile(name: String(localized: "Athletic Recovery (45 BPM)"), bpm: 45, lubBase: 40, lubDrop: 15, lubDecay: 16, dubBase: 50, dubDrop: 20, dubDecay: 20, dubDelay: 0.34, subFreq: 30, subVol: 0.50, subDecay: 5, whooshVol: 0.25, noiseLpf: 300),
		HeartbeatProfile(name: String(localized: "Gentle Drift (42 BPM)"), bpm: 42, lubBase: 32, lubDrop: 18, lubDecay: 14, dubBase: 38, dubDrop: 22, dubDecay: 16, dubDelay: 0.36, subFreq: 26, subVol: 0.55, subDecay: 4, whooshVol: 0.22, noiseLpf: 220),
		HeartbeatProfile(name: String(localized: "Deep Sleep Resonance (40 BPM)"), bpm: 40, lubBase: 30, lubDrop: 20, lubDecay: 12, dubBase: 35, dubDrop: 25, dubDecay: 15, dubDelay: 0.38, subFreq: 25, subVol: 0.60, subDecay: 4, whooshVol: 0.20, noiseLpf: 200),
		HeartbeatProfile(name: String(localized: "Hibernation State (35 BPM)"), bpm: 35, lubBase: 28, lubDrop: 20, lubDecay: 10, dubBase: 32, dubDrop: 25, dubDecay: 12, dubDelay: 0.40, subFreq: 22, subVol: 0.70, subDecay: 3, whooshVol: 0.15, noiseLpf: 180),
		HeartbeatProfile(name: String(localized: "Deep Trance (30 BPM)"), bpm: 30, lubBase: 25, lubDrop: 25, lubDecay: 10, dubBase: 30, dubDrop: 30, dubDecay: 12, dubDelay: 0.45, subFreq: 20, subVol: 0.75, subDecay: 3, whooshVol: 0.15, noiseLpf: 150),
		HeartbeatProfile(name: String(localized: "Slow Wave Sleep (25 BPM)"), bpm: 25, lubBase: 22, lubDrop: 25, lubDecay: 8, dubBase: 26, dubDrop: 30, dubDecay: 10, dubDelay: 0.50, subFreq: 18, subVol: 0.85, subDecay: 2, whooshVol: 0.10, noiseLpf: 130),
		HeartbeatProfile(name: String(localized: "Cinematic Oceanic (18 BPM)"), bpm: 18, lubBase: 25, lubDrop: 30, lubDecay: 8, dubBase: 30, dubDrop: 35, dubDecay: 10, dubDelay: 0.60, subFreq: 20, subVol: 0.90, subDecay: 2, whooshVol: 0.15, noiseLpf: 120),
		HeartbeatProfile(name: String(localized: "Soft Pillowy Pulse (62 BPM)"), bpm: 62, lubBase: 40, lubDrop: 15, lubDecay: 25, dubBase: 50, dubDrop: 20, dubDecay: 30, dubDelay: 0.28, subFreq: 32, subVol: 0.35, subDecay: 6, whooshVol: 0.20, noiseLpf: 250)
	]

	let panOptions = [
		String(localized: "Center"), String(localized: "Left"), String(localized: "Right"),
		String(localized: "Soft Left"), String(localized: "Soft Right"),
		String(localized: "1 Minute Slow Shift"), String(localized: "5 Minute Slow Shift"),
		String(localized: "30 Minute Extra Slow Shift"), String(localized: "1 Hour Extra Slow Shift")
	]
	let clockOptions = [
		String(localized: "Quartz Wall Clock"), String(localized: "Pocket Watch"),
		String(localized: "Grandfather Clock"), String(localized: "Metronome")
	]
	let placementOptions = [
		String(localized: "Center Beats & Flow"),
		String(localized: "Lub Left Ear / Dub Right Ear"),
		String(localized: "Lub Right Ear / Dub Left Ear")
	]
	let anchors = ["DRIFTING", "LETTING_GO", "DEEPER", "RELAX"]
	let reverbOptions = [
		String(localized: "Dry / No Reverb"), String(localized: "Small Room"),
		String(localized: "Medium Hall"), String(localized: "Large Hall"),
		String(localized: "Cathedral"), String(localized: "Medium Room"),
		String(localized: "Large Room"), String(localized: "Large Room 2")
	]
	let binauralOptions = [
		String(localized: "Delta Waves (2Hz - Deep Sleep)"),
		String(localized: "Theta Waves (6Hz - Dreaming)"),
		String(localized: "Alpha Waves (10Hz - Relaxation)")
	]

	private var renderState = AudioRenderState()

	@Published var selectedProfileIndex: Int = 0 { didSet { save("selectedProfileIndex", selectedProfileIndex); resetDynamicBPM(); rebuildPrototypes(); updateNowPlaying(); syncRenderState() } }
	@Published var placementIndex: Int = 0 { didSet { save("placementIndex", placementIndex); rebuildPrototypes(); syncRenderState() } }
	@Published var masterVolume: Double = 1.0 { didSet { save("masterVolume", masterVolume); updateVolumes() } }

	@Published var heartbeatVolume: Double = 0.0 { didSet { save("heartbeatVolume", heartbeatVolume); syncRenderState() } }
	@Published var faceBrushVolume: Double = 0.0 { didSet { save("faceBrushVolume", faceBrushVolume); syncRenderState() } }
	@Published var clockVolume: Double = 0.0 { didSet { save("clockVolume", clockVolume); syncRenderState() } }
	@Published var softClickVolume: Double = 0.0 { didSet { save("softClickVolume", softClickVolume); syncRenderState() } }
	@Published var brownVolume: Double = 0.0 { didSet { save("brownVolume", brownVolume); syncRenderState() } }
	@Published var whiteVolume: Double = 0.0 { didSet { save("whiteVolume", whiteVolume); syncRenderState() } }
	@Published var breathVolume: Double = 0.0 { didSet { save("breathVolume", breathVolume); syncRenderState() } }
	@Published var clickVolume: Double = 0.0 { didSet { save("clickVolume", clickVolume); syncRenderState() } }
	@Published var binauralVolume: Double = 0.0 { didSet { save("binauralVolume", binauralVolume); syncRenderState() } }

	@Published var rainVolume: Double = 0.0 { didSet { save("rainVolume", rainVolume); updateVolumes() } }
	@Published var organicHeartbeatVolume: Double = 0.0 { didSet { save("organicHeartbeatVolume", organicHeartbeatVolume); updateVolumes() } }

	@Published var panHeartIndex: Int = 0 { didSet { save("panHeartIndex", panHeartIndex); syncRenderState() } }
	@Published var panClockIndex: Int = 0 { didSet { save("panClockIndex", panClockIndex); syncRenderState() } }
	@Published var panBrownIndex: Int = 0 { didSet { save("panBrownIndex", panBrownIndex); syncRenderState() } }
	@Published var panWhiteIndex: Int = 0 { didSet { save("panWhiteIndex", panWhiteIndex); syncRenderState() } }
	@Published var panBreathIndex: Int = 0 { didSet { save("panBreathIndex", panBreathIndex); syncRenderState() } }
	@Published var panClickIndex: Int = 0 { didSet { save("panClickIndex", panClickIndex); syncRenderState() } }
	@Published var panSoftClickIndex: Int = 0 { didSet { save("panSoftClickIndex", panSoftClickIndex); syncRenderState() } }

	@Published var clockTypeIndex: Int = 0 { didSet { save("clockTypeIndex", clockTypeIndex); rebuildPrototypes(); syncRenderState() } }
	@Published var clickPatternIndex: Int = 0 { didSet { save("clickPatternIndex", clickPatternIndex); syncRenderState() } }
	@Published var softClickBoostEnabled: Bool = false { didSet { save("softClickBoostEnabled", softClickBoostEnabled); syncRenderState() } }
	@Published var binauralTypeIndex: Int = 0 { didSet { save("binauralTypeIndex", binauralTypeIndex); syncRenderState() } }
	@Published var syncClock: Bool = false { didSet { save("syncClock", syncClock); syncRenderState() } }
	@Published var syncClick: Bool = true { didSet { save("syncClick", syncClick); syncRenderState() } }
	@Published var enableRSA: Bool = false { didSet { save("enableRSA", enableRSA); syncRenderState() } }

	@Published var mixWithOthers: Bool = false { didSet { save("mixWithOthers", mixWithOthers); applyAudioSessionSettings() } }
	@Published var fadeToSilentOnHeadphoneRemoval: Bool = false { didSet { save("fadeToSilentOnHeadphoneRemoval", fadeToSilentOnHeadphoneRemoval) } }
	@Published var useWhisper: Bool = false { didSet { save("useWhisper", useWhisper) } }
	@Published var useRealBreathing: Bool = true { didSet { save("useRealBreathing", useRealBreathing); syncRenderState() } }

	@Published var enableHaptics: Bool = false { didSet { save("enableHaptics", enableHaptics) } }
	@Published var enableEnhancedAnchors: Bool = false { didSet { save("enableEnhancedAnchors", enableEnhancedAnchors) } }
	@Published var enableIntimateMode: Bool = false { didSet { save("enableIntimateMode", enableIntimateMode); updateProximityEQ(); syncRenderState() } }
	@Published var reverbIndex: Int = 0 { didSet { save("reverbIndex", reverbIndex); updateReverb() } }
	@Published var voiceInReverb: Bool = false { didSet { save("voiceInReverb", voiceInReverb); updateVoiceRouting() } }
	@Published var importedAudioInReverb: Bool = false { didSet { save("importedAudioInReverb", importedAudioInReverb); reloadImportedTracksRouting() } }
	@Published var enableHSPMode: Bool = false { didSet { save("enableHSPMode", enableHSPMode); updateHSPMode() } }
	@Published var meditationInHSP: Bool = true { didSet { save("meditationInHSP", meditationInHSP); loadMeditationTracks() } }
	@Published var enableDeepSleepDive: Bool = false { didSet { save("enableDeepSleepDive", enableDeepSleepDive) } }

	@Published var enableSlowdown: Bool = false { didSet { save("enableSlowdown", enableSlowdown); syncRenderState() } }
	@Published var targetBPM: Double = 40.0 { didSet { save("targetBPM", targetBPM); syncRenderState() } }
	@Published var slowdownMinutes: Double = 30.0 { didSet { save("slowdownMinutes", slowdownMinutes); syncRenderState() } }

	@Published var syncBreathing: Bool = false { didSet { save("syncBreathing", syncBreathing); syncRenderState() } }
	@Published var isBreathing: Bool = false { didSet { syncRenderState() } }
	@Published var manualBreathState: Int = 0 { didSet { syncRenderState() } }

	@Published var savedTracksJSON: Data = Data() { didSet { save("savedTracksJSON", savedTracksJSON) } }

	@Published var enableSleepTimer: Bool = false {
		didSet {
			save("enableSleepTimer", enableSleepTimer)
			if enableSleepTimer && isPlaying && sleepTimerStartDate == nil {
				sleepTimerStartDate = Date()
			}
		}
	}
	@Published var sleepTimerHours: Double = 3.0 { didSet { save("sleepTimerHours", sleepTimerHours) } }
	@Published var sleepFadeMinutes: Double = 45.0 { didSet { save("sleepFadeMinutes", sleepFadeMinutes) } }

	var sleepTimerStartDate: Date?

	@Published var enableMorningAlarm: Bool = false { didSet { save("enableMorningAlarm", enableMorningAlarm); updateSilentBackgroundAudio() } }
	@Published var morningAlarmDate: Date = Date() { didSet { save("morningAlarmDate", morningAlarmDate); activeMorningAlarmDate = nil } }
	@Published var morningSoundscapeFadeMinutes: Double = 20.0 { didSet { save("morningSoundscapeFadeMinutes", morningSoundscapeFadeMinutes) } }
	@Published var alarmVolume: Double = 1.0 { didSet { save("alarmVolume", alarmVolume); updateVolumes() } }
	@Published var alarmPath: String = "" { didSet { save("alarmPath", alarmPath) } }
	@Published var alarmIsAppleMusic: Bool = false { didSet { save("alarmIsAppleMusic", alarmIsAppleMusic) } }
	@Published var alarmNameStorage: String = "None" { didSet { save("alarmNameStorage", alarmNameStorage) } }
	@Published var isAlarmRinging: Bool = false

	private var alarmAutomationArmed = false
	private var morningAlarmPhase: MorningAlarmPhase = .idle
	private var activeMorningAlarmDate: Date?
	private var lastAlarmFireDayKey = ""
	private let alarmCrossfadeDuration: TimeInterval = 60.0
	private var wasPlayingBeforeInterruption = false
	private var wasAlarmRingingBeforeInterruption = false
	private var suppressRemotePauseUntil = Date.distantPast
	private var headphoneRemovalFadeTimer: Timer?
	private var headphoneRemovalSilentMode = false

	@Published var meditationPaths: [String] = [] { didSet { save("meditationPaths", meditationPaths) } }
	@Published var meditationIsAppleMusic: Bool = false { didSet { save("meditationIsAppleMusic", meditationIsAppleMusic) } }
	@Published var meditationNameStorage: String = "None" { didSet { save("meditationNameStorage", meditationNameStorage) } }

	var isMeditationActive = false
	var postMeditationPhase = false
	var meditationTotalDuration: TimeInterval = 0
	var meditationElapsedTime: TimeInterval = 0
	var postMeditationTime: TimeInterval = 0
	var currentMeditationIndex = 0

	var fadeTimer: Timer?
	private var simulationTask: DispatchWorkItem?

	private var lubL = [Float]()
	private var lubR = [Float]()
	private var dubL = [Float]()
	private var dubR = [Float]()
	private var lubEnv = [Float]()
	private var dubEnv = [Float]()
	private var nBeat = 0

	private var brownL = [Float]()
	private var brownR = [Float]()
	private var faceBrushL = [Float]()
	private var faceBrushR = [Float]()
	private var whiteL = [Float]()
	private var whiteR = [Float]()
	private var breathL = [Float]()
	private var breathR = [Float]()
	private var whooshL = [Float]()
	private var whooshR = [Float]()
	private var clk = [Float]()

	private var realInhaleBuffer = [Float]()
	private var realExhaleBuffer = [Float]()
	private var clickBuffer = [Float]()
	private var clickSoftBuffer = [Float]()

	private var nNoise = 0
	private var frameIdx = 0
	private let sampleRate: Double = 44100.0

	private var currentDynamicBPM: Double = 60.0
	private var startBPM: Double = 60.0
	private var tBeat: Double = 0.0
	private var beatCounter: Int = 0
	private var clkPlayIdx: Int = Int.max
	private var clkPlayIdx2: Int = Int.max
	private var clickPlayIdx: Int = Int.max
	private var softClickPlayIdx: Int = Int.max

	private var smoothedVHeart: Float = 0.0
	private var smoothedVFaceBrush: Float = 0.0
	private var smoothedVClock: Float = 0.0
	private var smoothedVBrown: Float = 0.0
	private var smoothedVWhite: Float = 0.0
	private var smoothedVBreath: Float = 0.0
	private var smoothedVClick: Float = 0.0
	private var smoothedVSoftClick: Float = 0.0
	private var smoothedVBinaural: Float = 0.0

	private var binauralPhaseL: Double = 0.0
	private var binauralPhaseR: Double = 0.0

	private var breathFrameCounter: Int = 0
	private var lastManualState: Int = 0
	private var syncedRealBreathSampleIndex: Int = 0
	private var syncedRealBreathSegment: Int = 0

	private var breathingTask: Task<Void, Never>?
	private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
	@Published var currentBreathingPhase: String = String(localized: "Ready")

	let isExporter: Bool

	init(isExporter: Bool = false) {
		self.isExporter = isExporter
		super.init()

		let ud = UserDefaults.standard
		self.selectedProfileIndex = ud.integer(forKey: "selectedProfileIndex")
		self.placementIndex = ud.integer(forKey: "placementIndex")
		self.masterVolume = ud.object(forKey: "masterVolume") == nil ? 1.0 : ud.double(forKey: "masterVolume")

		self.heartbeatVolume = ud.double(forKey: "heartbeatVolume")
		self.faceBrushVolume = ud.double(forKey: "faceBrushVolume")
		self.clockVolume = ud.double(forKey: "clockVolume")
		self.softClickVolume = ud.double(forKey: "softClickVolume")
		self.brownVolume = ud.double(forKey: "brownVolume")
		self.whiteVolume = ud.double(forKey: "whiteVolume")
		self.breathVolume = ud.double(forKey: "breathVolume")
		self.clickVolume = ud.double(forKey: "clickVolume")
		self.binauralVolume = ud.double(forKey: "binauralVolume")
		self.rainVolume = ud.double(forKey: "rainVolume")
		self.organicHeartbeatVolume = ud.double(forKey: "organicHeartbeatVolume")

		self.panHeartIndex = ud.integer(forKey: "panHeartIndex")
		self.panClockIndex = ud.integer(forKey: "panClockIndex")
		self.panBrownIndex = ud.integer(forKey: "panBrownIndex")
		self.panWhiteIndex = ud.integer(forKey: "panWhiteIndex")
		self.panBreathIndex = ud.integer(forKey: "panBreathIndex")
		self.panClickIndex = ud.integer(forKey: "panClickIndex")
		self.panSoftClickIndex = ud.object(forKey: "panSoftClickIndex") == nil ? self.panClickIndex : ud.integer(forKey: "panSoftClickIndex")

		self.clockTypeIndex = ud.integer(forKey: "clockTypeIndex")
		self.clickPatternIndex = ud.integer(forKey: "clickPatternIndex")
		self.softClickBoostEnabled = ud.bool(forKey: "softClickBoostEnabled")
		self.binauralTypeIndex = ud.integer(forKey: "binauralTypeIndex")
		self.syncClock = ud.bool(forKey: "syncClock")
		self.syncClick = ud.object(forKey: "syncClick") == nil ? true : ud.bool(forKey: "syncClick")
		self.enableRSA = ud.bool(forKey: "enableRSA")

		self.mixWithOthers = ud.bool(forKey: "mixWithOthers")
		self.fadeToSilentOnHeadphoneRemoval = ud.bool(forKey: "fadeToSilentOnHeadphoneRemoval")
		self.useWhisper = ud.bool(forKey: "useWhisper")
		self.useRealBreathing = ud.object(forKey: "useRealBreathing") == nil ? true : ud.bool(forKey: "useRealBreathing")

		self.enableHaptics = ud.bool(forKey: "enableHaptics")
		self.enableEnhancedAnchors = ud.bool(forKey: "enableEnhancedAnchors")
		self.enableIntimateMode = ud.bool(forKey: "enableIntimateMode")
		self.reverbIndex = ud.integer(forKey: "reverbIndex")
		self.voiceInReverb = ud.object(forKey: "voiceInReverb") == nil ? false : ud.bool(forKey: "voiceInReverb")
		self.importedAudioInReverb = ud.object(forKey: "importedAudioInReverb") == nil ? false : ud.bool(forKey: "importedAudioInReverb")
		self.enableHSPMode = ud.bool(forKey: "enableHSPMode")
		self.meditationInHSP = ud.object(forKey: "meditationInHSP") == nil ? true : ud.bool(forKey: "meditationInHSP")
		self.enableDeepSleepDive = ud.bool(forKey: "enableDeepSleepDive")

		self.enableSlowdown = ud.bool(forKey: "enableSlowdown")
		self.targetBPM = ud.object(forKey: "targetBPM") == nil ? 40.0 : ud.double(forKey: "targetBPM")
		self.slowdownMinutes = ud.object(forKey: "slowdownMinutes") == nil ? 30.0 : ud.double(forKey: "slowdownMinutes")

		self.syncBreathing = ud.bool(forKey: "syncBreathing")
		self.savedTracksJSON = ud.data(forKey: "savedTracksJSON") ?? Data()

		self.enableSleepTimer = ud.bool(forKey: "enableSleepTimer")
		self.sleepTimerHours = ud.object(forKey: "sleepTimerHours") == nil ? 3.0 : ud.double(forKey: "sleepTimerHours")
		self.sleepFadeMinutes = ud.object(forKey: "sleepFadeMinutes") == nil ? 45.0 : ud.double(forKey: "sleepFadeMinutes")
		self.enableMorningAlarm = ud.bool(forKey: "enableMorningAlarm")
		self.morningAlarmDate = ud.object(forKey: "morningAlarmDate") as? Date ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
		self.morningSoundscapeFadeMinutes = ud.object(forKey: "morningSoundscapeFadeMinutes") == nil ? 20.0 : ud.double(forKey: "morningSoundscapeFadeMinutes")
		self.alarmVolume = ud.object(forKey: "alarmVolume") == nil ? 1.0 : ud.double(forKey: "alarmVolume")
		self.alarmPath = ud.string(forKey: "alarmPath") ?? ""
		self.alarmIsAppleMusic = ud.bool(forKey: "alarmIsAppleMusic")
		self.alarmNameStorage = ud.string(forKey: "alarmNameStorage") ?? "None"

		self.meditationPaths = ud.stringArray(forKey: "meditationPaths") ?? []
		self.meditationIsAppleMusic = ud.bool(forKey: "meditationIsAppleMusic")
		self.meditationNameStorage = ud.string(forKey: "meditationNameStorage") ?? "None"

		hspEqNode.bands[0].filterType = .lowPass
		hspEqNode.bands[0].frequency = enableHSPMode ? 2500.0 : 20000.0
		hspEqNode.bands[0].bypass = !self.enableHSPMode

		proximityEqNode.bands[0].filterType = .lowShelf
		proximityEqNode.bands[0].frequency = 220.0
		proximityEqNode.bands[0].gain = 16.0
		proximityEqNode.bands[0].bypass = false

		proximityEqNode.bands[1].filterType = .highShelf
		proximityEqNode.bands[1].frequency = 4800.0
		proximityEqNode.bands[1].gain = 10.5
		proximityEqNode.bands[1].bypass = false

		proximityEqNode.bypass = !self.enableIntimateMode

		syncRenderState()
		if !isExporter {
			applyAudioSessionSettings()
		}
		setupOrganicPlayers()

		realInhaleBuffer = loadWAV(filename: "REAL_INHALE")
		realExhaleBuffer = loadWAV(filename: "REAL_EXHALE")
		clickBuffer = loadWAV(filename: "CLICK")
		clickSoftBuffer = loadWAV(filename: "CLICK_SOFT")

		setupAudio()

		loadTracks()
		loadMeditationTracks()
		loadAlarmPlayer()
		updateProximityEQ()
		resetDynamicBPM()
		rebuildPrototypes()
		updateVolumes()
		if !isExporter {
			setupMediaControls()
			setupObservers()
			setupCoreHaptics()
			startTimersMonitor()
		}
	}

	private func save(_ key: String, _ value: Any) {
		UserDefaults.standard.set(value, forKey: key)
	}

	private func syncRenderState() {
		var newState = AudioRenderState()
		newState.selectedProfileIndex = self.selectedProfileIndex
		newState.placementIndex = self.placementIndex
		newState.heartbeatVolume = Float(self.heartbeatVolume)
		newState.faceBrushVolume = Float(self.faceBrushVolume)
		newState.clockVolume = Float(self.clockVolume)
		newState.softClickVolume = Float(self.softClickVolume)
		newState.brownVolume = Float(self.brownVolume)
		newState.whiteVolume = Float(self.whiteVolume)
		newState.breathVolume = Float(self.breathVolume)
		newState.clickVolume = Float(self.clickVolume)
		newState.binauralVolume = Float(self.binauralVolume)
		newState.binauralTypeIndex = self.binauralTypeIndex
		newState.panHeartIndex = self.panHeartIndex
		newState.panClockIndex = self.panClockIndex
		newState.panBrownIndex = self.panBrownIndex
		newState.panWhiteIndex = self.panWhiteIndex
		newState.panBreathIndex = self.panBreathIndex
		newState.panClickIndex = self.panClickIndex
		newState.panSoftClickIndex = self.panSoftClickIndex
		newState.clockTypeIndex = self.clockTypeIndex
		newState.clickPatternIndex = self.clickPatternIndex
		newState.softClickBoostEnabled = self.softClickBoostEnabled
		newState.syncClock = self.syncClock
		newState.syncClick = self.syncClick
		newState.enableSlowdown = self.enableSlowdown
		newState.targetBPM = self.targetBPM
		newState.slowdownMinutes = self.slowdownMinutes
		newState.enableRSA = self.enableRSA
		newState.syncBreathing = self.syncBreathing
		newState.useRealBreathing = self.useRealBreathing
		newState.isBreathing = self.isBreathing
		newState.manualBreathState = self.manualBreathState
		newState.soundscapeMultiplier = Float(self.dynamicVolumeMultiplier * self.meditationFadeMultiplier * self.morningFadeMultiplier)
		newState.isPlaying = self.isPlaying
		newState.enableIntimateMode = self.enableIntimateMode
		self.renderState = newState
	}

	private func loadWAV(filename: String) -> [Float] {
		guard let url = Bundle.main.url(forResource: filename, withExtension: "wav"),
			  let file = try? AVAudioFile(forReading: url) else { return [] }

		guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
		do { try file.read(into: buffer) } catch { return [] }

		guard let channelData = buffer.floatChannelData?[0] else { return [] }
		return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
	}

	private func generatePingPongWavData(buffer: [Float], sampleRate: Double, duration: Double) -> URL? {
		if buffer.isEmpty || duration <= 0 { return nil }
		let frameCount = Int(duration * sampleRate)
		let tempDir = FileManager.default.temporaryDirectory
		let fileURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
		do {
			let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
			let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
			guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return nil }
			pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
			guard let channelData = pcmBuffer.floatChannelData?[0] else { return nil }
			let fadeFrames = Int(sampleRate * 0.3)
			for i in 0..<frameCount {
				let idx = getPingPongIndex(index: i, count: buffer.count)
				var env: Float = 1.0
				if i < fadeFrames {
					env = Float(i) / Float(fadeFrames)
				} else if i > frameCount - fadeFrames {
					env = Float(frameCount - i) / Float(fadeFrames)
				}
				let easedEnv = env * env * (3 - 2 * env)
				channelData[i] = buffer[idx] * easedEnv
			}
			try file.write(from: pcmBuffer)
			return fileURL
		} catch {
			return nil
		}
	}

	private func getPingPongIndex(index: Int, count: Int) -> Int {
		if count <= 0 { return 0 }
		let safeIndex = abs(index)
		let cycle = safeIndex % (2 * count)
		if cycle < count {
			return cycle
		} else {
			return 2 * count - cycle - 1
		}
	}

	private func setupCoreHaptics() {
		guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
		do {
			hapticEngine = try CHHapticEngine()
			try hapticEngine?.start()
			hapticEngine?.stoppedHandler = { reason in print("Haptic Engine stopped") }
			hapticEngine?.resetHandler = { do { try self.hapticEngine?.start() } catch {} }
		} catch {}
	}

	func triggerCustomHeartbeatHaptic(isLub: Bool) {
		guard enableHaptics, CHHapticEngine.capabilitiesForHardware().supportsHaptics, let engine = hapticEngine else { return }
		let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: isLub ? 1.0 : 0.6)
		let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.0)
		let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
		do {
			let pattern = try CHHapticPattern(events: [event], parameters: [])
			let player = try engine.makePlayer(with: pattern)
			try player.start(atTime: 0)
		} catch {}
	}

	func exportSoundscape(durationHours: Double, useAAC: Bool, simulatedStartDate: Date = Date(), progress: @escaping (Double) -> Void, completion: @escaping (URL?) -> Void) {
		DispatchQueue.global(qos: .userInitiated).async {
			let exporter = AudioEngineManager(isExporter: true)
			exporter.isPlaying = true
			exporter.updateVolumes()
			
			if !exporter.alarmIsAppleMusic && !exporter.alarmPath.isEmpty {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let url = docs.appendingPathComponent(exporter.alarmPath)
				if let af = try? AVAudioFile(forReading: url) {
					let node = AVAudioPlayerNode()
					exporter.engine.attach(node)
					exporter.engine.connect(node, to: exporter.engine.mainMixerNode, format: af.processingFormat)
					exporter.exporterAlarmNode = node
					exporter.exporterAlarmFile = af
				}
			}

			let format = AVAudioFormat(standardFormatWithSampleRate: exporter.sampleRate, channels: 2)!
			let maxFrames: AVAudioFrameCount = 16384
			do {
				try exporter.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
				try exporter.engine.start()
				
				let durationInSeconds = durationHours * 3600.0
				
				if let rNode = exporter.rainPlayerNode, let rFile = exporter.rainAudioFile {
					let fileLength = Double(rFile.length) / rFile.fileFormat.sampleRate
					let loops = Int(ceil(durationInSeconds / fileLength)) + 5
					for _ in 0..<loops { rNode.scheduleFile(rFile, at: nil, completionHandler: nil) }
					rNode.play()
				}
				
				if let hNode = exporter.organicHeartbeatPlayerNode, let hFile = exporter.organicHeartbeatAudioFile {
					let fileLength = Double(hFile.length) / hFile.fileFormat.sampleRate
					let loops = Int(ceil(durationInSeconds / fileLength)) + 5
					for _ in 0..<loops { hNode.scheduleFile(hFile, at: nil, completionHandler: nil) }
					hNode.play()
				}
				
				for track in exporter.importedTracks {
					if let tNode = track.enginePlayerNode, let tFile = track.audioFile {
						let fileLength = Double(tFile.length) / tFile.fileFormat.sampleRate
						let loops = Int(ceil(durationInSeconds / fileLength)) + 5
						for _ in 0..<loops { tNode.scheduleFile(tFile, at: nil, completionHandler: nil) }
						tNode.play()
					}
				}
				
				let tempDir = FileManager.default.temporaryDirectory
				let fileURL = tempDir.appendingPathComponent("SleepEngine_Export_\(UUID().uuidString).m4a")
				
				var settings = format.settings
				if useAAC {
					settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
					settings[AVEncoderBitRateKey] = 256000
				} else {
					settings[AVFormatIDKey] = kAudioFormatAppleLossless
				}
				let file = try AVAudioFile(forWriting: fileURL, settings: settings)
				
				let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maxFrames)!
				
				let totalFrames = Int64(durationHours * 3600.0 * exporter.sampleRate)
				var framesRendered: Int64 = 0
				var lastReportedPercent: Int = -1
				
				while framesRendered < totalFrames {
					let framesToRender = min(Int64(maxFrames), totalFrames - framesRendered)
					let simulatedNow = simulatedStartDate.addingTimeInterval(Double(framesRendered) / exporter.sampleRate)
					exporter.checkTimers(now: simulatedNow)
					
					let status = try exporter.engine.renderOffline(AVAudioFrameCount(framesToRender), to: buffer)
					if status == .success {
						try file.write(from: buffer)
						framesRendered += framesToRender
						
						let currentProgress = Double(framesRendered) / Double(totalFrames)
						let percent = Int(currentProgress * 100)
						if percent > lastReportedPercent {
							lastReportedPercent = percent
							DispatchQueue.main.async { progress(currentProgress) }
						}
					} else if status == .error {
						break
					}
				}
				
				exporter.engine.stop()
				DispatchQueue.main.async { completion(fileURL) }
			} catch {
				DispatchQueue.main.async { completion(nil) }
			}
		}
	}

	private func applyAudioSessionSettings() {
		do {
			let session = AVAudioSession.sharedInstance()
			var options: AVAudioSession.CategoryOptions = []
			if mixWithOthers { options.insert(.mixWithOthers) }
			try session.setCategory(.playback, mode: .default, options: options)
			try session.setPreferredSampleRate(sampleRate)
			try session.setActive(true, options: .notifyOthersOnDeactivation)
		} catch {}
	}

	private func makeSilentWavURL() -> URL? {
		let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("SleepEngine-Silent-Keeper.wav")
		if FileManager.default.fileExists(atPath: fileURL.path) { return fileURL }

		do {
			let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
			let frameCount = AVAudioFrameCount(sampleRate * 2.0)
			let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
			guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
			buffer.frameLength = frameCount
			try file.write(from: buffer)
			return fileURL
		} catch {
			return nil
		}
	}

	private func updateSilentBackgroundAudio() {
		let shouldKeepAlive = isPlaying || headphoneRemovalSilentMode || (enableMorningAlarm && alarmAutomationArmed && morningAlarmPhase != .idle)
		if shouldKeepAlive {
			ensureSilentBackgroundAudio()
		} else {
			silentBackgroundPlayer?.stop()
			silentBackgroundPlayer = nil
		}
	}

	private func ensureSilentBackgroundAudio() {
		applyAudioSessionSettings()
		if silentBackgroundPlayer == nil, let url = makeSilentWavURL() {
			silentBackgroundPlayer = try? AVAudioPlayer(contentsOf: url)
			silentBackgroundPlayer?.numberOfLoops = -1
			silentBackgroundPlayer?.volume = 1.0
			silentBackgroundPlayer?.prepareToPlay()
		}
		if silentBackgroundPlayer?.isPlaying != true {
			silentBackgroundPlayer?.play()
		}
	}

	func updateReverb() {
		switch reverbIndex {
		case 1:
			reverbNode.loadFactoryPreset(.smallRoom)
			reverbNode.wetDryMix = 30
		case 2:
			reverbNode.loadFactoryPreset(.mediumHall)
			reverbNode.wetDryMix = 40
		case 3:
			reverbNode.loadFactoryPreset(.largeHall)
			reverbNode.wetDryMix = 50
		case 4:
			reverbNode.loadFactoryPreset(.cathedral)
			reverbNode.wetDryMix = 60
		case 5:
			reverbNode.loadFactoryPreset(.mediumRoom)
			reverbNode.wetDryMix = 35
		case 6:
			reverbNode.loadFactoryPreset(.largeRoom)
			reverbNode.wetDryMix = 45
		case 7:
			reverbNode.loadFactoryPreset(.largeRoom2)
			reverbNode.wetDryMix = 45
		default:
			reverbNode.wetDryMix = 0
		}
	}

	func updateProximityEQ() {
		proximityEqNode.bypass = !enableIntimateMode
	}

	func updateHSPMode() {
		hspEqNode.bands[0].bypass = !enableHSPMode
		if enableHSPMode {
			hspEqNode.bands[0].frequency = 2500.0
		} else {
			hspEqNode.bands[0].frequency = 20000.0
		}
	}

	func updateVoiceRouting() {
		guard sourceNode != nil else { return }
		let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

		engine.disconnectNodeOutput(breathingNode)
		engine.disconnectNodeOutput(anchorNode)

		if voiceInReverb {
			engine.connect(breathingNode, to: preReverbMixer, format: format)
			engine.connect(anchorNode, to: preReverbMixer, format: format)
		} else {
			engine.connect(breathingNode, to: postReverbMixer, format: format)
			engine.connect(anchorNode, to: postReverbMixer, format: format)
		}
	}

	private func updateVolumes() {
		let soundscapeMultiplier = Float(dynamicVolumeMultiplier * meditationFadeMultiplier * morningFadeMultiplier)

		engine.mainMixerNode.outputVolume = Float(masterVolume)

		let targetRainVol = Float(rainVolume * masterVolume) * soundscapeMultiplier
		rainPlayerNode?.volume = targetRainVol

		let targetOrgVol = Float(organicHeartbeatVolume * masterVolume) * soundscapeMultiplier
		organicHeartbeatPlayerNode?.volume = targetOrgVol

		importedMixer.outputVolume = 1.0

		let baseVoiceVol = Float(masterVolume) * soundscapeMultiplier
		breathingNode.volume = useRealBreathing ? (baseVoiceVol * 4.0) : baseVoiceVol
		anchorNode.volume = baseVoiceVol * 2.0

		for track in importedTracks {
			track.masterVolume = masterVolume
			track.dynamicVolumeMultiplier = dynamicVolumeMultiplier
			track.meditationFadeMultiplier = meditationFadeMultiplier * morningFadeMultiplier
			track.postMeditationMultiplier = postMeditationMultiplier * morningFadeMultiplier
		}

		alarmPlayer?.volume = Float(alarmVolume * masterVolume * alarmFadeMultiplier)
		exporterAlarmNode?.volume = Float(alarmVolume * masterVolume * alarmFadeMultiplier)

		syncRenderState()
	}

	private func resetDynamicBPM() {
		currentDynamicBPM = profiles[selectedProfileIndex].bpm
		startBPM = currentDynamicBPM
		if targetBPM > startBPM { targetBPM = startBPM }
		tBeat = 0
		beatCounter = 0
		clkPlayIdx = Int.max
		clkPlayIdx2 = Int.max
		clickPlayIdx = Int.max
		softClickPlayIdx = Int.max
		smoothedVHeart = 0.0
		smoothedVFaceBrush = 0.0
		smoothedVClock = 0.0
		smoothedVBrown = 0.0
		smoothedVWhite = 0.0
		smoothedVBreath = 0.0
		smoothedVClick = 0.0
		smoothedVSoftClick = 0.0
		smoothedVBinaural = 0.0
		binauralPhaseL = 0.0
		binauralPhaseR = 0.0
		breathFrameCounter = 0
		lastManualState = 0
		syncedRealBreathSampleIndex = 0
		syncedRealBreathSegment = 0
	}

	private func loadPlayer(filename: String) -> AVAudioPlayer? {
		guard let url = Bundle.main.url(forResource: filename, withExtension: "wav") else { return nil }
		do {
			let player = try AVAudioPlayer(contentsOf: url)
			player.numberOfLoops = -1
			player.prepareToPlay()
			return player
		} catch { return nil }
	}

	private func setupOrganicPlayers() {
		if let url = Bundle.main.url(forResource: "RAIN", withExtension: "wav"),
		   let file = try? AVAudioFile(forReading: url) {
			rainAudioFile = file
			rainPlayerNode = AVAudioPlayerNode()
		}
		
		if let url = Bundle.main.url(forResource: "HEARTBEAT", withExtension: "wav"),
		   let file = try? AVAudioFile(forReading: url) {
			organicHeartbeatAudioFile = file
			organicHeartbeatPlayerNode = AVAudioPlayerNode()
		}
	}
	
	private func scheduleLoop(node: AVAudioPlayerNode?, file: AVAudioFile?) {
		guard let node = node, let file = file else { return }
		node.scheduleFile(file, at: nil) { [weak self] in
			DispatchQueue.main.async {
				self?.scheduleLoop(node: node, file: file)
			}
		}
	}

	func reloadImportedTracksRouting() {
		let currentlyPlaying = isPlaying
		if currentlyPlaying { stopSoundscape(keepEngineAlive: false) }

		for track in importedTracks {
			track.stop()
			if let pNode = track.enginePlayerNode {
				if pNode.engine != nil {
					engine.detach(pNode)
				}
			}
			track.enginePlayerNode = nil
			track.audioFile = nil
			track.avPlayer = nil

			if !track.isAppleMusic {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let url = docs.appendingPathComponent(track.path)

				if importedAudioInReverb {
					let pNode = AVAudioPlayerNode()
					track.enginePlayerNode = pNode
					if let file = try? AVAudioFile(forReading: url) {
						track.audioFile = file
						engine.attach(pNode)
						engine.connect(pNode, to: importedMixer, format: file.processingFormat)
						track.scheduleNextLoop()
						track.scheduleNextLoop()
					}
				} else {
					track.avPlayer = try? AVAudioPlayer(contentsOf: url)
					track.avPlayer?.numberOfLoops = -1
					track.avPlayer?.prepareToPlay()
				}
			} else {
				if let pid = UInt64(track.path) {
					let query = MPMediaQuery.songs()
					let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
					query.addFilterPredicate(predicate)
					if let item = query.items?.first, let url = item.assetURL {
						track.avPlayer = try? AVAudioPlayer(contentsOf: url)
						track.avPlayer?.numberOfLoops = -1
						track.avPlayer?.prepareToPlay()
					}
				}
			}
		}

		if currentlyPlaying { playStop() }
	}

	func addFile(url: URL, isMeditation: Bool = false) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		let fm = FileManager.default
		let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let filename = UUID().uuidString + "-" + url.lastPathComponent
		let dest = docs.appendingPathComponent(filename)
		do {
			try fm.copyItem(at: url, to: dest)
			if isMeditation {
				meditationPaths = [filename]
				meditationIsAppleMusic = false
				meditationNameStorage = url.lastPathComponent
				loadMeditationTracks()
			} else {
				let track = ImportedTrack(id: UUID(), name: url.lastPathComponent, volume: 0.5, isAppleMusic: false, path: filename, delayAfterMeditation: false)

				if importedAudioInReverb {
					let pNode = AVAudioPlayerNode()
					track.enginePlayerNode = pNode
					if let file = try? AVAudioFile(forReading: dest) {
						track.audioFile = file
						engine.attach(pNode)
						engine.connect(pNode, to: importedMixer, format: file.processingFormat)
						track.scheduleNextLoop()
						track.scheduleNextLoop()
					}
				} else {
					track.avPlayer = try? AVAudioPlayer(contentsOf: dest)
					track.avPlayer?.numberOfLoops = -1
					track.avPlayer?.prepareToPlay()
				}

				track.masterVolume = masterVolume
				if isPlaying { track.play() }
				importedTracks.append(track)
				saveTracks()
			}
		} catch {}
	}

	func addAlarmFile(url: URL) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		let fm = FileManager.default
		let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let filename = UUID().uuidString + "-alarm-" + url.lastPathComponent
		let dest = docs.appendingPathComponent(filename)
		do {
			if !alarmIsAppleMusic && !alarmPath.isEmpty {
				let previous = docs.appendingPathComponent(alarmPath)
				try? fm.removeItem(at: previous)
			}
			try fm.copyItem(at: url, to: dest)
			alarmPath = filename
			alarmIsAppleMusic = false
			alarmNameStorage = url.lastPathComponent
			loadAlarmPlayer()
		} catch {}
	}

	func addAppleMusic(items: [MPMediaItem], isMeditation: Bool = false) {
		if isMeditation {
			meditationPaths = items.map { String($0.persistentID) }
			meditationIsAppleMusic = true
			if items.count > 1 {
				meditationNameStorage = items.first?.albumTitle ?? "Meditation Album"
			} else {
				meditationNameStorage = items.first?.title ?? "Meditation Track"
			}
			loadMeditationTracks()
		} else {
			for item in items {
				guard let url = item.assetURL else { continue }
				do {
					let player = try AVAudioPlayer(contentsOf: url)
					player.numberOfLoops = -1
					player.prepareToPlay()
					let track = ImportedTrack(name: item.title ?? "Unknown Track", volume: 0.5, isAppleMusic: true, path: String(item.persistentID))
					track.avPlayer = player
					track.masterVolume = masterVolume
					if isPlaying { track.play() }
					importedTracks.append(track)
					saveTracks()
				} catch {}
			}
		}
	}

	func addAlarmAppleMusic(item: MPMediaItem) {
		if !alarmIsAppleMusic && !alarmPath.isEmpty {
			let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			try? FileManager.default.removeItem(at: docs.appendingPathComponent(alarmPath))
		}
		alarmPath = String(item.persistentID)
		alarmIsAppleMusic = true
		alarmNameStorage = item.title ?? "Apple Music Alarm"
		loadAlarmPlayer()
	}

	func clearAlarmSound() {
		alarmPlayer?.stop()
		alarmPlayer = nil
		if !alarmIsAppleMusic && !alarmPath.isEmpty {
			let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			try? FileManager.default.removeItem(at: docs.appendingPathComponent(alarmPath))
		}
		alarmPath = ""
		alarmNameStorage = "None"
		alarmIsAppleMusic = false
	}

	func removeTracks(at offsets: IndexSet) {
		for index in offsets {
			let track = importedTracks[index]
			track.stop()
			if let pNode = track.enginePlayerNode {
				if pNode.engine != nil {
					engine.detach(pNode)
				}
			}
			track.enginePlayerNode = nil
			track.audioFile = nil

			if !track.isAppleMusic {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let fileURL = docs.appendingPathComponent(track.path)
				try? FileManager.default.removeItem(at: fileURL)
			}
		}
		importedTracks.remove(atOffsets: offsets)
		saveTracks()
	}

	func clearMeditation() {
		meditationItems.forEach { $0.avPlayer?.stop() }
		meditationPlayerNode.stop()
		meditationItems.removeAll()
		meditationPaths = []
		meditationNameStorage = "None"
		isMeditationActive = false
		postMeditationPhase = false
		meditationFadeMultiplier = 1.0
		postMeditationMultiplier = 1.0
	}

	func saveTracks() {
		let dataList = importedTracks.map { TrackData(id: $0.id, name: $0.name, path: $0.path, volume: $0.volume, isAppleMusic: $0.isAppleMusic, delayAfterMeditation: $0.delayAfterMeditation) }
		if let encoded = try? JSONEncoder().encode(dataList) { savedTracksJSON = encoded }
	}

	private func loadTracks() {
		guard let dataList = try? JSONDecoder().decode([TrackData].self, from: savedTracksJSON) else { return }
		for data in dataList {
			if data.isAppleMusic {
				if let pid = UInt64(data.path) {
					let query = MPMediaQuery.songs()
					let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
					query.addFilterPredicate(predicate)
					if let item = query.items?.first, let url = item.assetURL {
						let avPlayer = try? AVAudioPlayer(contentsOf: url)
						avPlayer?.numberOfLoops = -1
						avPlayer?.prepareToPlay()
						let track = ImportedTrack(id: data.id, name: data.name, volume: data.volume, isAppleMusic: true, path: data.path, delayAfterMeditation: data.delayAfterMeditation)
						track.avPlayer = avPlayer
						track.masterVolume = masterVolume
						importedTracks.append(track)
					}
				}
			} else {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let url = docs.appendingPathComponent(data.path)
				let track = ImportedTrack(id: data.id, name: data.name, volume: data.volume, isAppleMusic: false, path: data.path, delayAfterMeditation: data.delayAfterMeditation)

				if importedAudioInReverb {
					let pNode = AVAudioPlayerNode()
					track.enginePlayerNode = pNode
					if let file = try? AVAudioFile(forReading: url) {
						track.audioFile = file
						engine.attach(pNode)
						engine.connect(pNode, to: importedMixer, format: file.processingFormat)
						track.scheduleNextLoop()
						track.scheduleNextLoop()
					}
				} else {
					track.avPlayer = try? AVAudioPlayer(contentsOf: url)
					track.avPlayer?.numberOfLoops = -1
					track.avPlayer?.prepareToPlay()
				}

				track.masterVolume = masterVolume
				importedTracks.append(track)
			}
		}
	}

	private func loadMeditationTracks() {
		meditationItems.forEach { $0.avPlayer?.stop() }
		meditationPlayerNode.stop()
		meditationItems.removeAll()
		meditationTotalDuration = 0

		for path in meditationPaths {
			var targetURL: URL?
			if meditationIsAppleMusic {
				if let pid = UInt64(path) {
					let query = MPMediaQuery.songs()
					let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
					query.addFilterPredicate(predicate)
					targetURL = query.items?.first?.assetURL
				}
			} else {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				targetURL = docs.appendingPathComponent(path)
			}

			guard let url = targetURL else { continue }
			var item = MeditationItem()

			if meditationInHSP {
				if let file = try? AVAudioFile(forReading: url) {
					item.audioFile = file
					item.duration = Double(file.length) / file.processingFormat.sampleRate
				} else if let player = try? AVAudioPlayer(contentsOf: url) {
					player.numberOfLoops = 0
					player.prepareToPlay()
					player.delegate = self
					item.avPlayer = player
					item.duration = player.duration
				}
			} else {
				if let player = try? AVAudioPlayer(contentsOf: url) {
					player.numberOfLoops = 0
					player.prepareToPlay()
					player.delegate = self
					item.avPlayer = player
					item.duration = player.duration
				}
			}

			if item.avPlayer != nil || item.audioFile != nil {
				meditationTotalDuration += item.duration
				meditationItems.append(item)
			}
		}
	}

	private func loadAlarmPlayer() {
		alarmPlayer?.stop()
		alarmPlayer = nil
		guard !alarmPath.isEmpty else { return }

		var targetURL: URL?
		if alarmIsAppleMusic {
			if let pid = UInt64(alarmPath) {
				let query = MPMediaQuery.songs()
				let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
				query.addFilterPredicate(predicate)
				targetURL = query.items?.first?.assetURL
			}
		} else {
			let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			targetURL = docs.appendingPathComponent(alarmPath)
		}

		guard let url = targetURL, let player = try? AVAudioPlayer(contentsOf: url) else { return }
		player.numberOfLoops = -1
		player.volume = Float(alarmVolume * masterVolume * alarmFadeMultiplier)
		player.prepareToPlay()
		alarmPlayer = player
	}

	func playMeditationTrack(at index: Int) {
		guard index < meditationItems.count else {
			isMeditationActive = false
			postMeditationPhase = true
			postMeditationTime = 0
			meditationFadeMultiplier = 1.0
			return
		}
		let item = meditationItems[index]
		if let player = item.avPlayer {
			player.play()
		} else if let file = item.audioFile {
			meditationPlayerNode.scheduleFile(file, at: nil) { [weak self] in
				DispatchQueue.main.async {
					guard let self = self else { return }
					if self.isMeditationActive && self.currentMeditationIndex == index && self.isPlaying {
						self.currentMeditationIndex += 1
						self.playMeditationTrack(at: self.currentMeditationIndex)
					}
				}
			}
			if !meditationPlayerNode.isPlaying {
				meditationPlayerNode.play()
			}
		}
	}

	func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			if self.isMeditationActive && !self.meditationItems.isEmpty {
				if self.currentMeditationIndex < self.meditationItems.count,
				   self.meditationItems[self.currentMeditationIndex].avPlayer == player {
					self.currentMeditationIndex += 1
					self.playMeditationTrack(at: self.currentMeditationIndex)
				}
			}
		}
	}

	private func startTimersMonitor() {
		fadeTimer?.invalidate()
		fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
			self?.checkTimers()
		}
	}

	func checkTimers(now: Date = Date()) {
		updateMorningAlarm(now: now)

		if isPlaying && isMeditationActive && !meditationItems.isEmpty {
			let item = meditationItems[currentMeditationIndex]
			var isCurrentlyPlaying = false
			if let player = item.avPlayer {
				isCurrentlyPlaying = player.isPlaying
			} else if item.audioFile != nil {
				isCurrentlyPlaying = meditationPlayerNode.isPlaying
			}

			if isCurrentlyPlaying {
				meditationElapsedTime += 0.1
				meditationFadeMultiplier = min(1.0, meditationElapsedTime / max(1.0, meditationTotalDuration))
			}
		} else if isPlaying && postMeditationPhase {
			postMeditationTime += 0.1
			postMeditationMultiplier = min(1.0, postMeditationTime / 300.0)
			if postMeditationTime >= 300.0 {
				postMeditationPhase = false
			}
		}

		var targetCutoff: Float = enableHSPMode ? 2500.0 : 20000.0
		var shouldBypassEQ = !enableHSPMode

		if enableSleepTimer, let start = sleepTimerStartDate, isPlaying {
			let elapsed = now.timeIntervalSince(start)
			let playTime = sleepTimerHours * 3600.0
			let fadeTime = sleepFadeMinutes * 60.0

			if elapsed >= playTime + fadeTime {
				dynamicVolumeMultiplier = 0.0
				if enableDeepSleepDive { targetCutoff = 400.0; shouldBypassEQ = false }
				stopSoundscape(keepEngineAlive: enableMorningAlarm && alarmAutomationArmed)
			} else if elapsed >= playTime {
				let progress = (elapsed - playTime) / fadeTime
				dynamicVolumeMultiplier = 1.0 - progress
				if enableDeepSleepDive {
					let startFreq = enableHSPMode ? 2500.0 : 20000.0
					targetCutoff = Float(startFreq - (startFreq - 400.0) * progress)
					shouldBypassEQ = false
				}
			} else {
				dynamicVolumeMultiplier = 1.0
				if enableDeepSleepDive { shouldBypassEQ = false }
			}
		}

		hspEqNode.bands[0].frequency = targetCutoff
		hspEqNode.bands[0].bypass = shouldBypassEQ
	}

	private func updateMorningAlarm(now: Date) {
		guard enableMorningAlarm, alarmAutomationArmed, !alarmPath.isEmpty else { return }

		let alarmDate = activeMorningAlarmDate ?? nextAlarmDate(after: now)
		activeMorningAlarmDate = alarmDate
		let dayKey = dayKey(for: alarmDate)
		if lastAlarmFireDayKey == dayKey { return }

		let shouldFadeInSoundscape = morningSoundscapeFadeMinutes > 0
		let fadeDuration = morningSoundscapeFadeMinutes * 60.0
		let fadeStart = shouldFadeInSoundscape ? alarmDate.addingTimeInterval(-fadeDuration) : alarmDate

		if now < fadeStart {
			morningAlarmPhase = .waiting
			updateSilentBackgroundAudio()
			return
		}

		if shouldFadeInSoundscape && now >= fadeStart && now < alarmDate {
			if !isPlaying {
				startSoundscape(startMuted: true, announcement: nil, includeMeditation: false)
			}
			morningAlarmPhase = .soundscapeFadeIn
			dynamicVolumeMultiplier = 1.0
			morningFadeMultiplier = min(1.0, max(0.0, now.timeIntervalSince(fadeStart) / fadeDuration))
			alarmFadeMultiplier = 0.0
			updateSilentBackgroundAudio()
			return
		}

		let crossfadeEnd = alarmDate.addingTimeInterval(alarmCrossfadeDuration)
		if now >= alarmDate && now < crossfadeEnd {
			if morningAlarmPhase != .alarmCrossfade {
				beginAlarmCrossfade()
			}
			let progress = min(1.0, max(0.0, now.timeIntervalSince(alarmDate) / alarmCrossfadeDuration))
			if shouldFadeInSoundscape {
				dynamicVolumeMultiplier = 1.0
			}
			morningFadeMultiplier = (shouldFadeInSoundscape || isPlaying) ? 1.0 - progress : 0.0
			alarmFadeMultiplier = progress
			if shouldFadeInSoundscape && !isPlaying {
				startSoundscape(startMuted: false, announcement: nil, includeMeditation: false)
			}
			updateSilentBackgroundAudio()
			return
		}

		if now >= crossfadeEnd {
			morningFadeMultiplier = 0.0
			alarmFadeMultiplier = 1.0
			lastAlarmFireDayKey = dayKey
			morningAlarmPhase = .ringing
			isAlarmRinging = true
			stopSoundscape(keepEngineAlive: true)
			updateNowPlaying(title: "Morning Alarm")
			updateSilentBackgroundAudio()
		}
	}

	private func beginAlarmCrossfade() {
		if isExporter {
			if let node = exporterAlarmNode, let file = exporterAlarmFile {
				node.volume = 0
				for _ in 0..<50 {
					node.scheduleFile(file, at: nil, completionHandler: nil)
				}
				node.play()
			}
		} else {
			if alarmPlayer == nil { loadAlarmPlayer() }
			alarmPlayer?.currentTime = 0
			alarmPlayer?.play()
		}
		alarmFadeMultiplier = 0.0
		isAlarmRinging = true
		morningAlarmPhase = .alarmCrossfade
		updateNowPlaying(title: "Morning Alarm")
	}

	func stopAlarm() {
		if isExporter {
			exporterAlarmNode?.stop()
		} else {
			alarmPlayer?.stop()
			alarmPlayer?.currentTime = 0
		}
		alarmFadeMultiplier = 0.0
		morningFadeMultiplier = 1.0
		isAlarmRinging = false
		morningAlarmPhase = .idle
		alarmAutomationArmed = false
		updateSilentBackgroundAudio()
		updateNowPlaying()
	}

	private func dayKey(for date: Date) -> String {
		let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
		return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
	}

	private func nextAlarmDate(after date: Date) -> Date {
		let calendar = Calendar.current
		let hour = calendar.component(.hour, from: morningAlarmDate)
		let minute = calendar.component(.minute, from: morningAlarmDate)
		let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
		if today > date { return today }
		return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
	}

	func stopSoundscape(keepEngineAlive: Bool) {
		headphoneRemovalFadeTimer?.invalidate()
		headphoneRemovalFadeTimer = nil
		rainPlayerNode?.pause()
		organicHeartbeatPlayerNode?.pause()
		for track in importedTracks { track.pause() }
		meditationItems.forEach { $0.avPlayer?.pause() }
		meditationPlayerNode.pause()
		isPlaying = false
		sleepTimerStartDate = nil
		UIAccessibility.post(notification: .announcement, argument: "Soundscape halted.")

		if !keepEngineAlive {
			headphoneRemovalSilentMode = false
			engine.pause()
		}
		updateSilentBackgroundAudio()
	}

	func simulateNightFadeOut() {
		simulationTask?.cancel()
		if !isPlaying { playStop() }
		dynamicVolumeMultiplier = 1.0
		var fadeStep = 0
		let totalSteps = Int(sleepFadeMinutes * 60.0 * 10)
		fadeTimer?.invalidate()
		fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
			guard let self = self else { return }
			fadeStep += 1
			let progress = Double(fadeStep) / Double(totalSteps)
			self.dynamicVolumeMultiplier = 1.0 - progress

			if self.enableDeepSleepDive {
				let startFreq = self.enableHSPMode ? 2500.0 : 20000.0
				let targetCutoff = Float(startFreq - (startFreq - 400.0) * progress)
				self.hspEqNode.bands[0].frequency = targetCutoff
				self.hspEqNode.bands[0].bypass = false
			} else {
				self.hspEqNode.bands[0].frequency = self.enableHSPMode ? 2500.0 : 20000.0
				self.hspEqNode.bands[0].bypass = !self.enableHSPMode
			}

			if fadeStep >= totalSteps {
				timer.invalidate()
				if self.isPlaying { self.stopSoundscape(keepEngineAlive: false) }
				self.dynamicVolumeMultiplier = 1.0
				self.updateHSPMode()
			}
		}
	}

	func playBreathingCue(type: String, duration: Double = 0.0, isAnchor: Bool = false) {
		let isBreathAction = (type == "INHALE" || type == "EXHALE")
		let node = isAnchor ? anchorNode : breathingNode

		if useRealBreathing && type == "HOLD" && !isAnchor {
			node.stop()
			return
		}

		if useRealBreathing && isBreathAction && duration > 0 {
			let buffer = type == "INHALE" ? realInhaleBuffer : realExhaleBuffer
			if let wavURL = generatePingPongWavData(buffer: buffer, sampleRate: sampleRate, duration: duration),
			   let file = try? AVAudioFile(forReading: wavURL) {
				node.stop()
				node.pan = getPanPos(mode: panBreathIndex, time: 0)
				node.scheduleFile(file, at: nil)
				node.play()
				return
			}
		}

		var filename = "\(type)\(useWhisper ? "_WHISPER" : "")"
		if useRealBreathing && isBreathAction { filename = "REAL_\(type)" }

		guard let url = Bundle.main.url(forResource: filename, withExtension: "wav"),
			  let file = try? AVAudioFile(forReading: url) else { return }

		node.stop()
		node.pan = isAnchor ? Float.random(in: -0.8...0.8) : getPanPos(mode: panBreathIndex, time: 0)

		if useRealBreathing && isBreathAction && !isAnchor {
			node.scheduleFile(file, at: nil) { [weak self] in self?.loopBreathingNode(node: node, file: file) }
		} else {
			node.scheduleFile(file, at: nil)
		}
		node.play()
	}

	private func loopBreathingNode(node: AVAudioPlayerNode, file: AVAudioFile) {
		if isBreathing {
			node.scheduleFile(file, at: nil) { [weak self] in self?.loopBreathingNode(node: node, file: file) }
		}
	}

	func startBreathingExercise(inhale: Int, hold1: Int, exhale: Int, hold2: Int) {
		breathingTask?.cancel()
		isBreathing = true
		backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BreathingExercise") { [weak self] in
			self?.stopBreathingExercise()
		}
		do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
		breathingTask = Task {
			while !Task.isCancelled {
				await MainActor.run {
					currentBreathingPhase = "Inhale (\(inhale)s)"
					manualBreathState = 1
					playBreathingCue(type: "INHALE", duration: Double(inhale))
				}
				try? await Task.sleep(nanoseconds: UInt64(inhale) * 1_000_000_000)
				if Task.isCancelled { break }
				if hold1 > 0 {
					await MainActor.run {
						currentBreathingPhase = "Hold (\(hold1)s)"
						manualBreathState = 3
						if enableEnhancedAnchors && Bool.random() && !useRealBreathing {
							playBreathingCue(type: anchors.randomElement()!, isAnchor: true)
						} else {
							playBreathingCue(type: "HOLD")
						}
					}
					try? await Task.sleep(nanoseconds: UInt64(hold1) * 1_000_000_000)
					if Task.isCancelled { break }
				}
				await MainActor.run {
					currentBreathingPhase = "Exhale (\(exhale)s)"
					manualBreathState = 2
					playBreathingCue(type: "EXHALE", duration: Double(exhale))
				}
				try? await Task.sleep(nanoseconds: UInt64(exhale) * 1_000_000_000)
				if Task.isCancelled { break }
				if hold2 > 0 {
					await MainActor.run {
						currentBreathingPhase = "Hold (\(hold2)s)"
						manualBreathState = 3
						if enableEnhancedAnchors && Bool.random() && !useRealBreathing {
							playBreathingCue(type: anchors.randomElement()!, isAnchor: true)
						} else {
							playBreathingCue(type: "HOLD")
						}
					}
					try? await Task.sleep(nanoseconds: UInt64(hold2) * 1_000_000_000)
				}
			}
			if backgroundTaskID != .invalid {
				UIApplication.shared.endBackgroundTask(backgroundTaskID)
				backgroundTaskID = .invalid
			}
		}
	}

	func stopBreathingExercise() {
		breathingTask?.cancel()
		isBreathing = false
		manualBreathState = 0
		currentBreathingPhase = String(localized: "Ready")
		breathingNode.stop()
		anchorNode.stop()
		if backgroundTaskID != .invalid {
			UIApplication.shared.endBackgroundTask(backgroundTaskID)
			backgroundTaskID = .invalid
		}
	}

	private func setupAudio() {
		let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
		sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
			guard let self = self else { return noErr }
			let state = self.renderState
			let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)

			if !state.isPlaying {
				for frame in 0..<Int(frameCount) {
					ablPointer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = 0.0
					ablPointer[1].mData?.assumingMemoryBound(to: Float.self)[frame] = 0.0
				}
				return noErr
			}

			let lubL = self.lubL; let dubL = self.dubL; let lubR = self.lubR; let dubR = self.dubR
			let lubEnv = self.lubEnv; let dubEnv = self.dubEnv; let brownL = self.brownL; let brownR = self.brownR
			let whiteL = self.whiteL; let whiteR = self.whiteR
			let breathL = self.breathL; let breathR = self.breathR; let whooshL = self.whooshL; let whooshR = self.whooshR
			let faceBrushL = self.faceBrushL; let faceBrushR = self.faceBrushR
			let clk = self.clk; let click = self.clickBuffer; let clickSoft = self.clickSoftBuffer; let realInhale = self.realInhaleBuffer; let realExhale = self.realExhaleBuffer
			let nBeat = self.nBeat; let nNoise = self.nNoise
			let config = self.profiles[state.selectedProfileIndex]

			if nNoise == 0 || nBeat == 0 { return noErr }

			let targetVHeart = state.heartbeatVolume; let targetVClock = state.clockVolume
			let targetVBrown = state.brownVolume; let targetVBreath = state.breathVolume
			let targetVWhite = state.whiteVolume
			let targetVClick = state.clickVolume; let targetVSoftClick = state.softClickVolume
			let targetVBinaural = state.binauralVolume
			let targetVFaceBrush = state.faceBrushVolume

			let smoothFactor: Float = 0.005
			let dt = 1.0 / self.sampleRate
			let bpmDropRate = state.enableSlowdown ? ((self.startBPM - state.targetBPM) / (state.slowdownMinutes * 60.0 * self.sampleRate)) : 0.0
			let ptrL = ablPointer[0].mData?.assumingMemoryBound(to: Float.self)
			let ptrR = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)

			for frame in 0..<Int(frameCount) {
				self.smoothedVHeart += (targetVHeart - self.smoothedVHeart) * smoothFactor
				self.smoothedVFaceBrush += (targetVFaceBrush - self.smoothedVFaceBrush) * smoothFactor
				self.smoothedVClock += (targetVClock - self.smoothedVClock) * smoothFactor
				self.smoothedVBrown += (targetVBrown - self.smoothedVBrown) * smoothFactor
				self.smoothedVWhite += (targetVWhite - self.smoothedVWhite) * smoothFactor
				self.smoothedVBreath += (targetVBreath - self.smoothedVBreath) * smoothFactor
				self.smoothedVClick += (targetVClick - self.smoothedVClick) * smoothFactor
				self.smoothedVSoftClick += (targetVSoftClick - self.smoothedVSoftClick) * smoothFactor
				self.smoothedVBinaural += (targetVBinaural - self.smoothedVBinaural) * smoothFactor

				let vHeart = self.smoothedVHeart; let vFaceBrush = self.smoothedVFaceBrush; let vClock = self.smoothedVClock; let vBrown = self.smoothedVBrown
				let vWhite = self.smoothedVWhite
				let vBreath = self.smoothedVBreath; let vClick = self.smoothedVClick; let vSoftClick = self.smoothedVSoftClick; let vBinaural = self.smoothedVBinaural
				let softClickBoost: Float = state.softClickBoostEnabled ? 2.5 : 1.0
				let totalGain = 1.0 + (vClock * 0.4) + (vBrown * 0.5) + (vWhite * 0.5) + (vBreath * 0.2) + (vClick * 0.3) + (vSoftClick * 0.3 * softClickBoost) + (vBinaural * 0.4) + (vFaceBrush * 0.3)

				let currentFrame = self.frameIdx + frame
				let timeInSeconds = Double(currentFrame) / self.sampleRate
				let tChunk = Float(timeInSeconds)

				var hL: Float = 0; var hR: Float = 0; var flowEnv: Float = 0

				var actualBPM = self.currentDynamicBPM
				if state.enableRSA {
					actualBPM += sin(2.0 * Double.pi * timeInSeconds / 6.0) * 4.0
				}

				if state.enableSlowdown {
					if bpmDropRate > 0 && self.currentDynamicBPM > state.targetBPM {
						self.currentDynamicBPM -= bpmDropRate
						if self.currentDynamicBPM < state.targetBPM { self.currentDynamicBPM = state.targetBPM }
					} else if bpmDropRate < 0 && self.currentDynamicBPM < state.targetBPM {
						self.currentDynamicBPM -= bpmDropRate
						if self.currentDynamicBPM > state.targetBPM { self.currentDynamicBPM = state.targetBPM }
					}
					actualBPM = self.currentDynamicBPM
					if state.enableRSA { actualBPM += sin(2.0 * Double.pi * timeInSeconds / 6.0) * 4.0 }
				}

				let beatDuration = 60.0 / actualBPM
				let previousTBeat = self.tBeat
				self.tBeat += dt

				let isBeat = self.tBeat >= beatDuration
				let isHalfBeat = previousTBeat < (beatDuration / 2.0) && self.tBeat >= (beatDuration / 2.0)

				if isBeat {
					self.tBeat -= beatDuration
					self.beatCounter += 1
					self.clkPlayIdx = 0

					if state.syncClick {
						if state.clickPatternIndex == 0 {
							self.clickPlayIdx = 0
							self.softClickPlayIdx = 0
						} else if state.clickPatternIndex == 1 {
							self.clickPlayIdx = 0
						} else if state.clickPatternIndex == 2 {
							self.softClickPlayIdx = 0
						}
					}

					DispatchQueue.main.async { self.triggerCustomHeartbeatHaptic(isLub: true) }
				}

				let ticksPerBeat = state.clockTypeIndex == 1 ? 2 : 1

				if isHalfBeat {
					if ticksPerBeat == 2 { self.clkPlayIdx2 = 0 }
					if state.syncClick {
						if state.clickPatternIndex == 1 {
							self.softClickPlayIdx = 0
						} else if state.clickPatternIndex == 2 {
							self.clickPlayIdx = 0
						}
					}
				}

				let t = self.tBeat
				let isDub = previousTBeat < config.dubDelay && t >= config.dubDelay
				if isDub { DispatchQueue.main.async { self.triggerCustomHeartbeatHaptic(isLub: false) } }

				let atk = 0.04; let rel = 0.02
				var lEnv = exp(-config.lubDecay * t); var slEnv = exp(-config.subDecay * t)
				if t < atk {
					let attackCurve = pow(sin((Double.pi / 2.0) * t / atk), 2)
					lEnv *= attackCurve; slEnv *= attackCurve
				}
				if t > beatDuration - rel {
					let releaseCurve = pow(cos((Double.pi / 2.0) * (t - (beatDuration - rel)) / rel), 2)
					lEnv *= releaseCurve; slEnv *= releaseCurve
				}
				let subLub = sin(2 * Double.pi * config.subFreq * t) * slEnv * config.subVol
				let lubPhase = 2 * Double.pi * (config.lubBase * t - (config.lubDrop / config.lubDecay) * exp(-config.lubDecay * t))
				let lub = sin(lubPhase) * lEnv

				var dEnv = 0.0; var sdEnv = 0.0; var subDub = 0.0; var dub = 0.0
				if t >= config.dubDelay {
					let tAct = t - config.dubDelay
					dEnv = exp(-config.dubDecay * tAct); sdEnv = exp(-config.subDecay * tAct)
					if tAct < atk {
						let attackCurve = pow(sin((Double.pi / 2.0) * tAct / atk), 2)
						dEnv *= attackCurve; sdEnv *= attackCurve
					}
					if t > beatDuration - rel {
						let releaseCurve = pow(cos((Double.pi / 2.0) * (t - (beatDuration - rel)) / rel), 2)
						dEnv *= releaseCurve; sdEnv *= releaseCurve
					}
					subDub = sin(2 * Double.pi * config.subFreq * t) * sdEnv * config.subVol * 0.85
					let dubPhase = 2 * Double.pi * (config.dubBase * tAct - (config.dubDrop / config.dubDecay) * exp(-config.dubDecay * tAct))
					dub = sin(dubPhase) * dEnv
				}

				let combinedLub = Float((lub + subLub) * 0.8); let combinedDub = Float((dub + subDub) * 0.8)
				
				if state.placementIndex == 0 {
					hL = (combinedLub + combinedDub) * 0.85; hR = (combinedLub + combinedDub) * 0.85
				} else if state.placementIndex == 1 {
					hL = combinedLub; hR = combinedDub
				} else {
					hL = combinedDub; hR = combinedLub
				}
				flowEnv = 0.6 + 0.4 * Float(lEnv + dEnv)

				if !state.syncClick {
					let halfSec = Int(self.sampleRate / 2.0)
					let remainder = currentFrame % Int(self.sampleRate)
					if remainder == 0 {
						if state.clickPatternIndex == 0 {
							self.clickPlayIdx = 0
							self.softClickPlayIdx = 0
						} else if state.clickPatternIndex == 1 {
							self.clickPlayIdx = 0
						} else if state.clickPatternIndex == 2 {
							self.softClickPlayIdx = 0
						}
					} else if remainder == halfSec {
						if state.clickPatternIndex == 1 {
							self.softClickPlayIdx = 0
						} else if state.clickPatternIndex == 2 {
							self.clickPlayIdx = 0
						}
					}
				}

				let idxNoise = currentFrame % nNoise
				let wVol = Float(config.whooshVol)
				hL += whooshL[idxNoise] * flowEnv * wVol; hR += whooshR[idxNoise] * flowEnv * wVol
				let posH = self.getPanPos(mode: state.panHeartIndex, time: tChunk)
				let (chunkHL, chunkHR) = self.applyStereoPan(inL: hL, inR: hR, pos: posH, vol: vHeart, intimate: state.enableIntimateMode)

				var chunkCL: Float = 0; var chunkCR: Float = 0
				if vClock > 0 {
					var clkWave: Float = 0
					if state.syncClock {
						if self.clkPlayIdx < clk.count { clkWave += clk[self.clkPlayIdx]; self.clkPlayIdx += 1 }
						if self.clkPlayIdx2 < clk.count { clkWave += clk[self.clkPlayIdx2]; self.clkPlayIdx2 += 1 }
					} else { clkWave = clk[currentFrame % clk.count] }
					let posC = self.getPanPos(mode: state.panClockIndex, time: tChunk)
					let pannedC = self.applyStereoPan(inL: clkWave, inR: clkWave, pos: posC, vol: vClock * 0.4, intimate: state.enableIntimateMode)
					chunkCL = pannedC.0; chunkCR = pannedC.1
				}

				var chunkClickL: Float = 0; var chunkClickR: Float = 0
				if vClick > 0 && self.clickPlayIdx < click.count {
					let cSample = click[self.clickPlayIdx]
					let posClick = self.getPanPos(mode: state.panClickIndex, time: tChunk)
					let pannedClick = self.applyStereoPan(inL: cSample, inR: cSample, pos: posClick, vol: vClick * 0.8, intimate: state.enableIntimateMode)
					chunkClickL += pannedClick.0; chunkClickR += pannedClick.1
					self.clickPlayIdx += 1
				}
				if vSoftClick > 0 && self.softClickPlayIdx < clickSoft.count {
					let cSample = clickSoft[self.softClickPlayIdx]
					let posClick = self.getPanPos(mode: state.panSoftClickIndex, time: tChunk)
					let pannedClick = self.applyStereoPan(inL: cSample, inR: cSample, pos: posClick, vol: vSoftClick * 0.8 * softClickBoost, intimate: state.enableIntimateMode)
					chunkClickL += pannedClick.0; chunkClickR += pannedClick.1
					self.softClickPlayIdx += 1
				}

				var chunkBL: Float = 0; var chunkBR: Float = 0
				if vBrown > 0 {
					let posB = self.getPanPos(mode: state.panBrownIndex, time: tChunk)
					let pannedB = self.applyStereoPan(inL: brownL[idxNoise], inR: brownR[idxNoise], pos: posB, vol: vBrown * 0.5, intimate: state.enableIntimateMode)
					chunkBL = pannedB.0; chunkBR = pannedB.1
				}

				var chunkWL: Float = 0; var chunkWR: Float = 0
				if vWhite > 0 {
					let posW = self.getPanPos(mode: state.panWhiteIndex, time: tChunk)
					let pannedW = self.applyStereoPan(inL: whiteL[idxNoise], inR: whiteR[idxNoise], pos: posW, vol: vWhite * 0.5, intimate: state.enableIntimateMode)
					chunkWL = pannedW.0; chunkWR = pannedW.1
				}

				var chunkBinL: Float = 0; var chunkBinR: Float = 0
				if vBinaural > 0 {
					let baseFreq = 150.0
					let beatFreq = state.binauralTypeIndex == 0 ? 2.0 : (state.binauralTypeIndex == 1 ? 6.0 : 10.0)
					self.binauralPhaseL += 2.0 * Double.pi * baseFreq * dt
					self.binauralPhaseR += 2.0 * Double.pi * (baseFreq + beatFreq) * dt
					if self.binauralPhaseL > 2.0 * Double.pi { self.binauralPhaseL -= 2.0 * Double.pi }
					if self.binauralPhaseR > 2.0 * Double.pi { self.binauralPhaseR -= 2.0 * Double.pi }
					chunkBinL = Float(sin(self.binauralPhaseL)) * vBinaural * 0.4
					chunkBinR = Float(sin(self.binauralPhaseR)) * vBinaural * 0.4
				}

				var chunkBrL: Float = 0; var chunkBrR: Float = 0
				if vBreath > 0 && !state.isBreathing {
					var breathEnv: Float = 0; var sampleIdxForRealBreath = 0; var usingInhale = false; var usingExhale = false
					if state.syncBreathing {
						let syncPhase = Double(self.beatCounter % 8) + (self.tBeat / beatDuration)
						let phaseBeat = self.beatCounter % 8

						if phaseBeat < 4 {
							usingInhale = true
							let inhalePhase = Float(sin(Double.pi * syncPhase / 4.0))
							breathEnv = max(0.0, inhalePhase) * 0.8
						} else {
							usingExhale = true
							let exhalePhase = Float(sin(Double.pi * (syncPhase - 4.0) / 4.0))
							breathEnv = max(0.0, exhalePhase) * 0.6
						}

						if isBeat {
							if phaseBeat == 0 {
								DispatchQueue.main.async { self.currentBreathingPhase = "Inhale (Sync)"; if !state.useRealBreathing { self.playBreathingCue(type: "INHALE") } }
							} else if phaseBeat == 4 {
								DispatchQueue.main.async { self.currentBreathingPhase = "Exhale (Sync)"; if !state.useRealBreathing { self.playBreathingCue(type: "EXHALE") } }
							} else if phaseBeat == 2 && self.enableEnhancedAnchors && Bool.random() {
								let anchor = self.anchors.randomElement()!
								DispatchQueue.main.async { self.playBreathingCue(type: anchor, isAnchor: true) }
							}
						}

						if state.useRealBreathing {
							let currentSegment = usingInhale ? 1 : 2
							if currentSegment != self.syncedRealBreathSegment {
								self.syncedRealBreathSegment = currentSegment
								self.syncedRealBreathSampleIndex = 0
							}
							sampleIdxForRealBreath = self.syncedRealBreathSampleIndex
							self.syncedRealBreathSampleIndex += 1
						} else {
							if phaseBeat < 4 {
								sampleIdxForRealBreath = Int((syncPhase / 4.0) * (4.0 * beatDuration * self.sampleRate))
							} else {
								sampleIdxForRealBreath = Int(((syncPhase - 4.0) / 4.0) * (4.0 * beatDuration * self.sampleRate))
							}
						}
					} else {
						self.syncedRealBreathSegment = 0
						self.syncedRealBreathSampleIndex = 0
						let breathDuration = 6.0; let breathPhase = fmod(timeInSeconds, breathDuration) / breathDuration
						if breathPhase < 0.45 {
							usingInhale = true; let inhalePhase = Float(sin(Double.pi * (breathPhase / 0.45))); breathEnv = inhalePhase * 0.8
							sampleIdxForRealBreath = Int((breathPhase / 0.45) * (0.45 * breathDuration * self.sampleRate))
						} else if breathPhase >= 0.5 && breathPhase < 0.95 {
							usingExhale = true; let exhalePhase = Float(sin(Double.pi * ((breathPhase - 0.5) / 0.45))); breathEnv = exhalePhase * 0.6
							sampleIdxForRealBreath = Int(((breathPhase - 0.5) / 0.45) * (0.45 * breathDuration * self.sampleRate))
						}
					}

					var breathSampleL: Float = 0; var breathSampleR: Float = 0
					if state.useRealBreathing {
						if usingInhale && !realInhale.isEmpty {
							let idx = self.getPingPongIndex(index: sampleIdxForRealBreath, count: realInhale.count)
							breathSampleL = realInhale[idx]; breathSampleR = realInhale[idx]
						} else if usingExhale && !realExhale.isEmpty {
							let idx = self.getPingPongIndex(index: sampleIdxForRealBreath, count: realExhale.count)
							breathSampleL = realExhale[idx]; breathSampleR = realExhale[idx]
						}
					} else {
						breathSampleL = breathL[idxNoise]; breathSampleR = breathR[idxNoise]
					}
					let posBr = self.getPanPos(mode: state.panBreathIndex, time: tChunk)
					let realBreathVolMult: Float = state.useRealBreathing ? 10.0 : 2.5
					let pannedBr = self.applyStereoPan(inL: breathSampleL * breathEnv, inR: breathSampleR * breathEnv, pos: posBr, vol: vBreath * realBreathVolMult, intimate: state.enableIntimateMode)
					chunkBrL = pannedBr.0; chunkBrR = pannedBr.1
				}

				var chunkFaceBrushL: Float = 0; var chunkFaceBrushR: Float = 0
				if vFaceBrush > 0 && !faceBrushL.isEmpty {
					let idx = currentFrame % faceBrushL.count
					chunkFaceBrushL = faceBrushL[idx] * vFaceBrush * 1.5
					chunkFaceBrushR = faceBrushR[idx] * vFaceBrush * 1.5
				}

				let finalL = ((chunkHL + chunkCL + chunkBL + chunkWL + chunkBrL + chunkClickL + chunkBinL + chunkFaceBrushL) / totalGain) * state.soundscapeMultiplier
				let finalR = ((chunkHR + chunkCR + chunkBR + chunkWR + chunkBrR + chunkClickR + chunkBinR + chunkFaceBrushR) / totalGain) * state.soundscapeMultiplier
				ptrL?[frame] = finalL; ptrR?[frame] = finalR
			}
			self.frameIdx += Int(frameCount)
			return noErr
		}

		if let node = sourceNode {
			engine.attach(node)
			engine.attach(preReverbMixer)
			engine.attach(importedMixer)
			engine.attach(reverbNode)
			engine.attach(postReverbMixer)
			engine.attach(meditationPlayerNode)
			engine.attach(breathingNode)
			engine.attach(anchorNode)
			engine.attach(proximityEqNode)
			engine.attach(hspEqNode)

			if let rn = rainPlayerNode { engine.attach(rn) }
			if let hn = organicHeartbeatPlayerNode { engine.attach(hn) }

			engine.connect(node, to: preReverbMixer, format: format)
			engine.connect(importedMixer, to: preReverbMixer, format: format)

			if let rn = rainPlayerNode, let rf = rainAudioFile {
				engine.connect(rn, to: postReverbMixer, format: rf.processingFormat)
			}
			if let hn = organicHeartbeatPlayerNode, let hf = organicHeartbeatAudioFile {
				engine.connect(hn, to: postReverbMixer, format: hf.processingFormat)
			}

			engine.connect(preReverbMixer, to: reverbNode, format: format)
			engine.connect(reverbNode, to: postReverbMixer, format: format)
			engine.connect(meditationPlayerNode, to: postReverbMixer, format: format)

			engine.connect(postReverbMixer, to: proximityEqNode, format: format)
			engine.connect(proximityEqNode, to: hspEqNode, format: format)
			engine.connect(hspEqNode, to: engine.mainMixerNode, format: format)

			updateVoiceRouting()
			updateReverb()
			updateProximityEQ()
			updateHSPMode()
		}
	}

	private func getPanPos(mode: Int, time: Float) -> Float {
		switch mode {
		case 0: return 0.0
		case 1: return -1.0
		case 2: return 1.0
		case 3: return -0.5
		case 4: return 0.5
		case 5: return sin(2.0 * Float.pi * time / 60.0)
		case 6: return sin(2.0 * Float.pi * time / 300.0)
		case 7: return sin(2.0 * Float.pi * time / 1800.0)
		case 8: return sin(2.0 * Float.pi * time / 3600.0)
		default: return 0.0
		}
	}

	private func applyStereoPan(inL: Float, inR: Float, pos: Float, vol: Float, intimate: Bool) -> (Float, Float) {
		let bleedToL = pos < 0 ? abs(pos) : 0.0
		let bleedToR = pos > 0 ? pos : 0.0
		let keepL = pos > 0 ? 1.0 - pos : 1.0
		let keepR = pos < 0 ? 1.0 - abs(pos) : 1.0
		let norm = 1.0 + abs(pos)

		var outL = ((inL * keepL + inR * bleedToL) / norm) * vol
		var outR = ((inR * keepR + inL * bleedToR) / norm) * vol

		if intimate {
			let absPos = abs(pos)
			let closerEarBoost = Float(1.0 + absPos * 0.85)
			let oppositeEarReduction = Float(pow(Double(1.0 - absPos), 3.5))
			
			if pos > 0 {
				outR *= closerEarBoost
				outL *= oppositeEarReduction
			} else if pos < 0 {
				outL *= closerEarBoost
				outR *= oppositeEarReduction
			}
		}

		return (outL, outR)
	}

	private func gaussianRandom() -> Float {
		var u1: Float = 0
		repeat { u1 = Float.random(in: 0..<1) } while u1 == 0
		let u2 = Float.random(in: 0..<1)
		return sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
	}

	private func generateWhiteNoise(length: Int) -> [Float] {
		let crossfadeLength = Int(sampleRate * 2.0)
		let totalLength = length + crossfadeLength
		var noise = [Float](repeating: 0, count: totalLength)
		var maxVal: Float = 0
		for i in 0..<totalLength {
			noise[i] = gaussianRandom()
		}
		for i in 0..<crossfadeLength {
			let ratio = Float(i) / Float(crossfadeLength)
			let fadeOut = cos(ratio * Float.pi / 2.0)
			let fadeIn = sin(ratio * Float.pi / 2.0)
			noise[i] = (noise[length + i] * fadeOut) + (noise[i] * fadeIn)
		}
		var finalNoise = Array(noise[0..<length])
		for i in 0..<length { if abs(finalNoise[i]) > maxVal { maxVal = abs(finalNoise[i]) } }
		if maxVal > 0 { for i in 0..<length { finalNoise[i] /= maxVal } }
		return finalNoise
	}

	private func generateSeamlessNoise(length: Int, lpfFreq: Double? = nil, isBrown: Bool = false) -> [Float] {
		let crossfadeLength = Int(sampleRate * 2.0)
		let totalLength = length + crossfadeLength
		var noise = [Float](repeating: 0, count: totalLength)
		var maxVal: Float = 0; var lastBrown: Float = 0
		var filter1: Float = 0; var filter2: Float = 0; var filter3: Float = 0; var filter4: Float = 0
		let alpha: Float
		if let freq = lpfFreq {
			let dt = 1.0 / sampleRate; let rc = 1.0 / (2.0 * Double.pi * (freq * 0.5))
			alpha = Float(dt / (rc + dt))
		} else { alpha = 1.0 }

		for i in 0..<totalLength {
			let white = gaussianRandom(); lastBrown = 0.995 * lastBrown + 0.05 * white
			if isBrown { noise[i] = lastBrown } else {
				filter1 = filter1 + alpha * (lastBrown - filter1)
				filter2 = filter2 + alpha * (filter1 - filter2)
				filter3 = filter3 + alpha * (filter2 - filter3)
				filter4 = filter4 + alpha * (filter3 - filter4)
				noise[i] = filter4
			}
		}
		for i in 0..<crossfadeLength {
			let ratio = Float(i) / Float(crossfadeLength)
			let fadeOut = cos(ratio * Float.pi / 2.0); let fadeIn = sin(ratio * Float.pi / 2.0)
			noise[i] = (noise[length + i] * fadeOut) + (noise[i] * fadeIn)
		}
		var finalNoise = Array(noise[0..<length])
		for i in 0..<length { if abs(finalNoise[i]) > maxVal { maxVal = abs(finalNoise[i]) } }
		if maxVal > 0 { for i in 0..<length { finalNoise[i] /= maxVal } }
		return finalNoise
	}

	private func rebuildPrototypes() {
		let config = profiles[selectedProfileIndex]
		let bpm = config.bpm; nBeat = Int((60.0 / bpm) * sampleRate)
		let actualBeatDur = Double(nBeat) / sampleRate
		let atkSamples = Int(0.04 * sampleRate); let relSamples = Int(0.02 * sampleRate)
		let trueSubFreq = max(1, round(config.subFreq * actualBeatDur)) / actualBeatDur
		let idxStart = Int(config.dubDelay * sampleRate)
		let placementIndex = self.placementIndex

		var localLubL = [Float](repeating: 0, count: nBeat); var localLubR = [Float](repeating: 0, count: nBeat)
		var localDubL = [Float](repeating: 0, count: nBeat); var localDubR = [Float](repeating: 0, count: nBeat)
		var localLubEnv = [Float](repeating: 0, count: nBeat); var localDubEnv = [Float](repeating: 0, count: nBeat)

		for i in 0..<nBeat {
			let t = Double(i) / sampleRate
			var lEnv = exp(-config.lubDecay * t)
			if i < atkSamples { lEnv *= pow(sin((Double.pi / 2.0) * Double(i) / Double(atkSamples)), 2) }
			if i > nBeat - relSamples { lEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
			localLubEnv[i] = Float(lEnv)
			var sLEnv = exp(-config.subDecay * t)
			if i < atkSamples { sLEnv *= pow(sin((Double.pi / 2.0) * Double(i) / Double(atkSamples)), 2) }
			if i > nBeat - relSamples { sLEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
			let subLub = sin(2 * Double.pi * trueSubFreq * t) * sLEnv * config.subVol
			let lubPhase = 2 * Double.pi * (config.lubBase * t - (config.lubDrop / config.lubDecay) * exp(-config.lubDecay * t))
			let lub = sin(lubPhase) * lEnv

			var dEnv: Double = 0; var subDub: Double = 0; var dub: Double = 0
			if i >= idxStart {
				let tAct = t - config.dubDelay; dEnv = exp(-config.dubDecay * tAct)
				let relI = i - idxStart
				if relI < atkSamples { dEnv *= pow(sin((Double.pi / 2.0) * Double(relI) / Double(atkSamples)), 2) }
				if i > nBeat - relSamples { dEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
				var sDEnv = exp(-config.subDecay * tAct)
				if relI < atkSamples { sDEnv *= pow(sin((Double.pi / 2.0) * Double(relI) / Double(atkSamples)), 2) }
				if i > nBeat - relSamples { sDEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
				subDub = sin(2 * Double.pi * trueSubFreq * t) * sDEnv * config.subVol * 0.85
				let dubPhase = 2 * Double.pi * (config.dubBase * tAct - (config.dubDrop / config.dubDecay) * exp(-config.dubDecay * tAct))
				dub = sin(dubPhase) * dEnv
			}
			localDubEnv[i] = Float(dEnv)

			let combinedLub = Float((lub + subLub)); let combinedDub = Float((dub + subDub))
			if placementIndex == 0 {
				localLubL[i] = combinedLub * 0.85; localLubR[i] = combinedLub * 0.85
				localDubL[i] = combinedDub * 0.85; localDubR[i] = combinedDub * 0.85
			} else if placementIndex == 1 {
				localLubL[i] = combinedLub; localLubR[i] = 0; localDubL[i] = 0; localDubR[i] = combinedDub
			} else {
				localLubL[i] = 0; localLubR[i] = combinedLub; localDubL[i] = combinedDub; localDubR[i] = 0
			}
		}

		var globalPeak: Float = 0
		for i in 0..<nBeat {
			let peakL = abs(localLubL[i] + localDubL[i]); let peakR = abs(localLubR[i] + localDubR[i])
			if peakL > globalPeak { globalPeak = peakL }; if peakR > globalPeak { globalPeak = peakR }
		}
		if globalPeak > 0 {
			for i in 0..<nBeat {
				localLubL[i] = (localLubL[i] / globalPeak) * 0.70; localLubR[i] = (localLubR[i] / globalPeak) * 0.70
				localDubL[i] = (localDubL[i] / globalPeak) * 0.70; localDubR[i] = (localDubR[i] / globalPeak) * 0.70
			}
		}

		self.lubL = localLubL; self.lubR = localLubR; self.dubL = localDubL; self.dubR = localDubR
		self.lubEnv = localLubEnv; self.dubEnv = localDubEnv

		nNoise = Int(sampleRate * 30.0)
		if brownL.isEmpty {
			brownL = generateSeamlessNoise(length: nNoise, isBrown: true); brownR = generateSeamlessNoise(length: nNoise, isBrown: true)
			breathL = generateSeamlessNoise(length: nNoise, lpfFreq: 600); breathR = generateSeamlessNoise(length: nNoise, lpfFreq: 600)
		}
		whiteL = generateWhiteNoise(length: nNoise); whiteR = generateWhiteNoise(length: nNoise)
		whooshL = generateSeamlessNoise(length: nNoise, lpfFreq: config.noiseLpf); whooshR = generateSeamlessNoise(length: nNoise, lpfFreq: config.noiseLpf)

		// Synthesize continuous sweeping Gentle Face Brush (16 seconds loop of 4-second sweeps with randomized panning)
		let nFaceBrush = Int(sampleRate * 16.0)
		var localFaceBrushL = [Float](repeating: 0, count: nFaceBrush)
		var localFaceBrushR = [Float](repeating: 0, count: nFaceBrush)

		let brushLowFilter = BiQuadFilter()
		let brushHighFilter = BiQuadFilter()
		brushLowFilter.setLowpass(frequency: 65.0, Q: 0.7, sampleRate: sampleRate)
		brushHighFilter.setLowpass(frequency: 1200.0, Q: 0.5, sampleRate: sampleRate)

		// Choose a random sequence of panned positions for each of the 4 sweeps
		let possiblePans: [Float] = [-0.85, -0.6, -0.3, 0.0, 0.3, 0.6, 0.85]
		var randomBrushPans = [Float]()
		for _ in 0..<4 {
			randomBrushPans.append(possiblePans.randomElement()!)
		}

		for i in 0..<nFaceBrush {
			let t = Double(i) / sampleRate
			let sweepIndex = Int(t / 4.0)
			let s = (t - Double(sweepIndex) * 4.0) / 4.0 // 0.0 to 1.0 within the sweep
			let tPress = s * 4.0

			// Raised sine/cosine volume envelope for slow sweep touch-and-release
			var env: Double = 0.0
			if tPress < 1.2 {
				env = pow(sin((Double.pi / 2.0) * tPress / 1.2), 2)
			} else if tPress < 2.0 {
				env = 1.0
			} else if tPress < 3.5 {
				env = pow(cos((Double.pi / 2.0) * (tPress - 2.0) / 1.5), 2)
			} else {
				env = 0.0
			}

			// Panning position chosen randomly per sweep
			let p = randomBrushPans[sweepIndex % 4]

			// Organic hand micro-tremor (6Hz amplitude tremolo)
			let tremor = 0.88 + 0.12 * sin(2.0 * Double.pi * 6.0 * t)
			let noiseVal = gaussianRandom()
			
			// Exact soft touch implementation (low-frequency warm rumble + ultra-soft high-frequency contact friction)
			let rumble = brushLowFilter.process(Double(noiseVal))
			let friction = brushHighFilter.process(Double(noiseVal))
			let monoSample = Float((rumble * 1.5 + friction * 0.015) * env * tremor * 0.25)

			// Stereo Pan
			let absP = abs(p)
			let bleedToL = p < 0 ? absP : 0.0
			let bleedToR = p > 0 ? p : 0.0
			let keepL = p > 0 ? 1.0 - p : 1.0
			let keepR = p < 0 ? 1.0 - absP : 1.0
			let norm = 1.0 + absP

			var outL = (monoSample * keepL + monoSample * bleedToL) / norm
			var outR = (monoSample * keepR + monoSample * bleedToR) / norm

			// Intimate Proximity spatialization
			let closerEarBoost = 1.0 + absP * 0.85
			let oppositeEarReduction = pow(1.0 - absP, 3.5)
			if p > 0 {
				outR *= closerEarBoost
				outL *= oppositeEarReduction
			} else if p < 0 {
				outL *= closerEarBoost
				outR *= oppositeEarReduction
			}

			localFaceBrushL[i] = outL
			localFaceBrushR[i] = outR
		}
		self.faceBrushL = localFaceBrushL
		self.faceBrushR = localFaceBrushR

		let clockTypeIndex = self.clockTypeIndex; let nClockProto = Int(sampleRate * 1.5)
		clk = [Float](repeating: 0, count: nClockProto)
		for i in 0..<nClockProto {
			let tc = Double(i) / sampleRate; let randomGaussian = gaussianRandom() * 0.3
			if clockTypeIndex == 0 {
				let body = (sin(2 * Double.pi * 1200 * tc) * 0.15 + sin(2 * Double.pi * 2000 * tc) * 0.05) * exp(-120 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-300 * tc))
			} else if clockTypeIndex == 1 {
				let body = (sin(2 * Double.pi * 4000 * tc) * 0.1 + sin(2 * Double.pi * 6000 * tc) * 0.05) * exp(-200 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-800 * tc)) * 1.5
			} else if clockTypeIndex == 2 {
				let body = (sin(2 * Double.pi * 350 * tc) * 0.2 + sin(2 * Double.pi * 800 * tc) * 0.1) * exp(-60 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-500 * tc)) * 1.2
			} else {
				let body = (sin(2 * Double.pi * 1000 * tc) * 0.3 + sin(2 * Double.pi * 2000 * tc) * 0.1) * exp(-100 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-600 * tc)) * 1.2
			}
		}
	}

	func playStop() {
		if isAlarmRinging {
			stopAlarm()
			return
		}

		if isPlaying {
			stopSoundscape(keepEngineAlive: false)
			alarmAutomationArmed = false
			morningAlarmPhase = .idle
			activeMorningAlarmDate = nil
			morningFadeMultiplier = 1.0
			alarmFadeMultiplier = 0.0
			updateSilentBackgroundAudio()
		} else {
			if enableMorningAlarm && !alarmPath.isEmpty {
				alarmAutomationArmed = true
				morningAlarmPhase = .waiting
				activeMorningAlarmDate = nextAlarmDate(after: Date())
			}
			morningFadeMultiplier = 1.0
			alarmFadeMultiplier = 0.0
			startSoundscape(startMuted: false, announcement: "Audio stream active.", includeMeditation: true)
		}
	}

	private func startSoundscape(startMuted: Bool, announcement: String?, includeMeditation: Bool) {
		do {
			headphoneRemovalFadeTimer?.invalidate()
			headphoneRemovalFadeTimer = nil
			headphoneRemovalSilentMode = false
			applyAudioSessionSettings()

			if sourceNode == nil { setupAudio() }

			resetDynamicBPM()
			updateVoiceRouting()

			engine.prepare()

			if includeMeditation && !meditationItems.isEmpty {
				isMeditationActive = true
				currentMeditationIndex = 0
				meditationElapsedTime = 0
				meditationFadeMultiplier = 0.0
				postMeditationMultiplier = 0.0
				postMeditationPhase = false
			} else {
				isMeditationActive = false
				meditationFadeMultiplier = 1.0
				postMeditationMultiplier = 1.0
				postMeditationPhase = false
			}

			if startMuted {
				dynamicVolumeMultiplier = 1.0
				morningFadeMultiplier = 0.0
			} else {
				dynamicVolumeMultiplier = 1.0
			}

			updateVolumes()
			try engine.start()
			ensureSilentBackgroundAudio()

			sleepTimerStartDate = Date()

			DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
				guard let self = self else { return }
				guard self.engine.isRunning else { return }
				scheduleLoop(node: rainPlayerNode, file: rainAudioFile)
				scheduleLoop(node: organicHeartbeatPlayerNode, file: organicHeartbeatAudioFile)
				self.rainPlayerNode?.play()
				self.organicHeartbeatPlayerNode?.play()
				for track in self.importedTracks { track.play() }
				if self.isMeditationActive && !self.meditationItems.isEmpty {
					self.playMeditationTrack(at: self.currentMeditationIndex)
				}
				self.isPlaying = true
				self.updateNowPlaying()
				self.updateSilentBackgroundAudio()
				if let announcement = announcement {
					UIAccessibility.post(notification: .announcement, argument: announcement)
				}
			}
		} catch { print("Engine start error: \(error)") }
	}

	private func setupMediaControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		commandCenter.playCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if !self.isPlaying { self.playStop(); return .success }
			return .commandFailed
		}
		commandCenter.pauseCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if self.fadeToSilentOnHeadphoneRemoval && self.isPlaying {
				self.fadeToSilentAfterHeadphoneRemoval()
				return .success
			}
			if self.isPlaying || self.isAlarmRinging || Date() < self.suppressRemotePauseUntil {
				self.resumeAfterRouteChange()
				return .success
			}
			return .commandFailed
		}
		commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if self.fadeToSilentOnHeadphoneRemoval && self.isPlaying {
				self.fadeToSilentAfterHeadphoneRemoval()
				return .success
			}
			if self.isPlaying || self.isAlarmRinging {
				self.resumeAfterRouteChange()
				return .success
			}
			self.playStop()
			return .success
		}
	}

	private func pauseForInterruption() {
		wasPlayingBeforeInterruption = isPlaying
		wasAlarmRingingBeforeInterruption = isAlarmRinging
		rainPlayerNode?.pause()
		organicHeartbeatPlayerNode?.pause()
		for track in importedTracks { track.pause() }
		meditationItems.forEach { $0.avPlayer?.pause() }
		meditationPlayerNode.pause()
		alarmPlayer?.pause()
		updateSilentBackgroundAudio()
	}

	private func resumeAfterInterruption() {
		applyAudioSessionSettings()
		if wasPlayingBeforeInterruption {
			do {
				if !engine.isRunning {
					try engine.start()
				}
				rainPlayerNode?.play()
				organicHeartbeatPlayerNode?.play()
				for track in importedTracks { track.play() }
				if isMeditationActive && !meditationItems.isEmpty {
					playMeditationTrack(at: currentMeditationIndex)
				}
			} catch {}
		}
		if wasAlarmRingingBeforeInterruption || isAlarmRinging {
			alarmPlayer?.play()
		}
		wasPlayingBeforeInterruption = false
		wasAlarmRingingBeforeInterruption = false
		updateSilentBackgroundAudio()
	}

	private func fadeToSilentAfterHeadphoneRemoval() {
		guard isPlaying else {
			updateSilentBackgroundAudio()
			return
		}

		headphoneRemovalFadeTimer?.invalidate()
		let keepAlarmAlive = enableMorningAlarm && alarmAutomationArmed
		let startMultiplier = dynamicVolumeMultiplier
		var elapsed: TimeInterval = 0
		let duration: TimeInterval = 10.0
		ensureSilentBackgroundAudio()

		headphoneRemovalFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
			guard let self = self else {
				timer.invalidate()
				return
			}
			elapsed += 0.1
			let progress = min(1.0, elapsed / duration)
			self.dynamicVolumeMultiplier = startMultiplier * (1.0 - progress)

			if progress >= 1.0 {
				timer.invalidate()
				self.headphoneRemovalFadeTimer = nil
				self.headphoneRemovalSilentMode = keepAlarmAlive
				self.stopSoundscape(keepEngineAlive: keepAlarmAlive)
			}
		}
	}

	private func resumeAfterRouteChange() {
		suppressRemotePauseUntil = Date().addingTimeInterval(3.0)
		applyAudioSessionSettings()
		updateSilentBackgroundAudio()
		if isPlaying {
			do {
				if !engine.isRunning {
					try engine.start()
				}
				rainPlayerNode?.play()
				organicHeartbeatPlayerNode?.play()
				for track in importedTracks { track.play() }
				if isMeditationActive && !meditationItems.isEmpty {
					playMeditationTrack(at: currentMeditationIndex)
				}
			} catch {}
		}
		if isAlarmRinging {
			alarmPlayer?.play()
		}
	}

	private func updateNowPlaying(title: String? = nil) {
		var nowPlayingInfo = [String: Any]()
		nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? profiles[selectedProfileIndex].name
		nowPlayingInfo[MPMediaItemPropertyArtist] = "Sleep Engine"
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
	}

	private func setupObservers() {
		NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
			guard let self = self, let userInfo = notification.userInfo,
				  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
				  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
			if type == .began {
				self.pauseForInterruption()
			} else if type == .ended {
				guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
				let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
				if options.contains(.shouldResume) || self.wasPlayingBeforeInterruption || self.wasAlarmRingingBeforeInterruption {
					self.resumeAfterInterruption()
				}
			}
		}

		NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
			guard let self = self, let userInfo = notification.userInfo,
				  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
				  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
			if reason == .oldDeviceUnavailable && self.fadeToSilentOnHeadphoneRemoval {
				self.fadeToSilentAfterHeadphoneRemoval()
			} else if reason == .oldDeviceUnavailable || reason == .routeConfigurationChange || reason == .categoryChange || reason == .override {
				self.resumeAfterRouteChange()
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
					self.resumeAfterRouteChange()
				}
			}
		}

		NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
			guard let self = self else { return }
			if self.isPlaying {
				do {
					try self.engine.start()
					self.rainPlayerNode?.play()
					self.organicHeartbeatPlayerNode?.play()
					for track in self.importedTracks { track.play() }
					if self.isMeditationActive && !self.meditationItems.isEmpty {
						self.playMeditationTrack(at: self.currentMeditationIndex)
					}
				} catch {}
			}
		}

		NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
			guard let self = self else { return }
			if self.enableHaptics {
				do { try self.hapticEngine?.start() } catch { self.setupCoreHaptics() }
			}
		}
	}
}

// MARK: - Views

struct MediaPicker: UIViewControllerRepresentable {
	@Binding var isPresented: Bool
	var onPicked: (MPMediaItemCollection) -> Void

	func makeUIViewController(context: Context) -> MPMediaPickerController {
		let picker = MPMediaPickerController(mediaTypes: .anyAudio)
		picker.allowsPickingMultipleItems = true
		picker.showsCloudItems = false
		picker.delegate = context.coordinator
		return picker
	}

	func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}
	func makeCoordinator() -> Coordinator { Coordinator(self) }

	class Coordinator: NSObject, MPMediaPickerControllerDelegate {
		let parent: MediaPicker
		init(_ parent: MediaPicker) { self.parent = parent }
		func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
			parent.onPicked(mediaItemCollection)
			parent.isPresented = false
		}
		func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
			parent.isPresented = false
		}
	}
}

struct TrackRowView: View {
	@ObservedObject var track: ImportedTrack
	@ObservedObject var engine: AudioEngineManager

	var body: some View {
		VStack(alignment: .leading) {
			Text(track.name).font(.headline)
			Slider(value: $track.volume, in: 0...1)
				.accessibilityLabel("\(track.name) Volume")
				.onChange(of: track.volume) { _ in engine.saveTracks() }
			Toggle("Delay after Meditation", isOn: $track.delayAfterMeditation)
				.font(.caption)
				.onChange(of: track.delayAfterMeditation) { _ in engine.saveTracks() }
		}
		.padding(.vertical, 4)
	}
}

struct SoundscapeView: View {
	@ObservedObject var engine: AudioEngineManager
	@State private var showingFilePicker = false
	@State private var showingMusicPicker = false

	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("Organic Elements").accessibilityHidden(true)) {
					VStack(alignment: .leading) {
						Text("Rain Volume").accessibilityHidden(true)
						Slider(value: $engine.rainVolume, in: 0...1).accessibilityLabel("Rain Volume")
					}
					VStack(alignment: .leading) {
						Text("Organic Heartbeat Volume").accessibilityHidden(true)
						Slider(value: $engine.organicHeartbeatVolume, in: 0...1).accessibilityLabel("Organic Heartbeat Volume")
					}
				}
				Section(header: Text("Imported Audio")) {
					if engine.importedTracks.isEmpty {
						Text("No files imported.").foregroundColor(.secondary)
					} else {
						ForEach(engine.importedTracks) { track in
							TrackRowView(track: track, engine: engine)
						}.onDelete { offsets in engine.removeTracks(at: offsets) }
					}
				}
			}
			.navigationTitle("Soundscape")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarLeading) {
					Menu("Import") {
						Button("From Files") { showingFilePicker = true }
						Button("From Apple Music") { showingMusicPicker = true }
					}
				}
			}
			.fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
				switch result {
				case .success(let urls): for url in urls { engine.addFile(url: url) }
				case .failure(let error): print(error)
				}
			}
			.sheet(isPresented: $showingMusicPicker) {
				MediaPicker(isPresented: $showingMusicPicker) { items in
					engine.addAppleMusic(items: items.items)
				}
			}
		}
	}
}

struct GeneratorView: View {
	@ObservedObject var engine: AudioEngineManager
	var body: some View {
		Form {
			Section(header: Text("Base Speed & Tone Profile").accessibilityHidden(true)) {
				Picker("Tone Profile", selection: $engine.selectedProfileIndex) {
					ForEach(0..<engine.profiles.count, id: \.self) { index in
						Text(engine.profiles[index].name).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())
			}

			Section(header: Text("Heartbeat Dynamics").accessibilityHidden(true)) {
				Toggle("Fluid Slow Down Over Time", isOn: $engine.enableSlowdown)
				if engine.enableSlowdown {
					let maxBPM = engine.profiles[engine.selectedProfileIndex].bpm
					VStack(alignment: .leading) {
						Text("Target BPM: \(Int(engine.targetBPM))")
						Slider(value: Binding(
							get: { min(self.engine.targetBPM, maxBPM) },
							set: { self.engine.targetBPM = $0 }
						), in: 15...max(15, maxBPM), step: 1)
					}
					VStack(alignment: .leading) {
						Text("Duration: \(Int(engine.slowdownMinutes)) Minutes")
						Slider(value: $engine.slowdownMinutes, in: 5...120, step: 5)
					}
				}
				Toggle("Organic Human Variation (RSA)", isOn: $engine.enableRSA)
					.accessibilityHint("Naturally speeds up and slows down the heartbeat with a simulated breath cycle.")
			}

			Section(header: Text("Procedural Layer Mixer").accessibilityHidden(true)) {
				VStack(alignment: .leading) {
					Text("Synth Heartbeat").accessibilityHidden(true)
					Slider(value: $engine.heartbeatVolume, in: 0...1).accessibilityLabel("Synth Heartbeat Volume")
				}.padding(.vertical, 4)

				VStack(alignment: .leading) {
					Text("Clock Ticking").accessibilityHidden(true)
					Slider(value: $engine.clockVolume, in: 0...1).accessibilityLabel("Clock Volume")
					Picker("Clock Type", selection: $engine.clockTypeIndex) {
						ForEach(0..<engine.clockOptions.count, id: \.self) { index in
							Text(engine.clockOptions[index]).tag(index)
						}
					}
					.pickerStyle(MenuPickerStyle())
					Toggle("Sync to Heartbeat", isOn: $engine.syncClock)
				}.padding(.vertical, 4)

				VStack(alignment: .leading) {
					Text("Click Track").accessibilityHidden(true)
					Slider(value: $engine.clickVolume, in: 0...1).accessibilityLabel("Click Volume")

					Text("Soft Click Track").accessibilityHidden(true)
					Slider(value: $engine.softClickVolume, in: 0...1).accessibilityLabel("Soft Click Volume")
					Toggle("Boost Soft Click", isOn: $engine.softClickBoostEnabled)
						.accessibilityHint("Raises only the soft click layer above its normal slider range.")

					Picker("Click Pattern", selection: $engine.clickPatternIndex) {
						Text("Simultaneous").tag(0)
						Text("Tick-Tock (Normal First)").tag(1)
						Text("Tock-Tick (Soft First)").tag(2)
					}
					.pickerStyle(MenuPickerStyle())

					Toggle("Sync to Heartbeat", isOn: $engine.syncClick)
				}.padding(.vertical, 4)

				VStack(alignment: .leading) {
					Text("Absolute Room Masking (White Noise)").bold()
					Slider(value: $engine.whiteVolume, in: 0...1).accessibilityLabel("White Noise Volume")
				}.padding(.vertical, 4)

				VStack(alignment: .leading) {
					Text("Brown Noise").accessibilityHidden(true)
					Slider(value: $engine.brownVolume, in: 0...1).accessibilityLabel("Brown Noise Volume")
				}.padding(.vertical, 4)

				VStack(alignment: .leading) {
					Text("Slow Breathing Base").bold()
					Slider(value: $engine.breathVolume, in: 0...1).accessibilityLabel("Slow Breathing Volume")
				}.padding(.vertical, 4)

				VStack(alignment: .leading) {
					Text("Gentle Face Brush").bold()
					Slider(value: $engine.faceBrushVolume, in: 0...1).accessibilityLabel("Gentle Face Brush Volume")
				}.padding(.vertical, 4)
			}

			Section(header: Text("Binaural Brainwave Entrainment")) {
				VStack(alignment: .leading) {
					Text("Binaural Beat Volume").accessibilityHidden(true)
					Slider(value: $engine.binauralVolume, in: 0...1).accessibilityLabel("Binaural Beat Volume")
				}.padding(.vertical, 4)

				Picker("Entrainment Target", selection: $engine.binauralTypeIndex) {
					ForEach(0..<engine.binauralOptions.count, id: \.self) { index in
						Text(engine.binauralOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())
			}

			Section(header: Text("Spatial Audio Panning")) {
				Picker("Heartbeat Anatomy", selection: $engine.placementIndex) {
					ForEach(0..<engine.placementOptions.count, id: \.self) { index in
						Text(engine.placementOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("Heartbeat Position", selection: $engine.panHeartIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("Breathing Position", selection: $engine.panBreathIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("Clock Position", selection: $engine.panClockIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("Click Position", selection: $engine.panClickIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("Soft Click Position", selection: $engine.panSoftClickIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("White Noise Position", selection: $engine.panWhiteIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Picker("Brown Noise Position", selection: $engine.panBrownIndex) {
					ForEach(0..<engine.panOptions.count, id: \.self) { index in
						Text(engine.panOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())
			}
		}
	}
}

struct BreathingView: View {
	@ObservedObject var engine: AudioEngineManager
	var body: some View {
		VStack(spacing: 30) {
			Text(engine.currentBreathingPhase)
				.font(.largeTitle).bold()
				.accessibilityLabel("Current Phase: \(engine.currentBreathingPhase)")

			Toggle("Sync Cues to Heartbeat Rhythm", isOn: $engine.syncBreathing)
				.padding(.horizontal, 40)
				.onChange(of: engine.syncBreathing) { synced in
					if synced && engine.isBreathing { engine.stopBreathingExercise() }
				}

			if !engine.syncBreathing {
				HStack(spacing: 20) {
					Button("4-7-8 Relax") { engine.startBreathingExercise(inhale: 4, hold1: 7, exhale: 8, hold2: 0) }
						.buttonStyle(.borderedProminent).disabled(engine.isBreathing)
					Button("Box Breathing") { engine.startBreathingExercise(inhale: 4, hold1: 4, exhale: 4, hold2: 4) }
						.buttonStyle(.borderedProminent).disabled(engine.isBreathing)
				}
				if engine.isBreathing {
					Button("Stop Exercise") { engine.stopBreathingExercise() }
						.foregroundColor(.red).padding(.top, 20)
				}
			} else {
				Text("Manual exercises are disabled because breathing is actively bound to the heartbeat BPM.")
					.font(.footnote)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal, 40)
			}
		}
	}
}

struct SleepTimerView: View {
	private enum FileImportTarget {
		case meditation
		case alarm
	}

	@ObservedObject var engine: AudioEngineManager
	@State private var showingMeditationMusicPicker = false
	@State private var showingAlarmMusicPicker = false
	@State private var showingFilePicker = false
	@State private var fileImportTarget: FileImportTarget?

	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("Night Fade-Out (Sleep Timer)")) {
					Toggle("Enable Night Fade-Out", isOn: $engine.enableSleepTimer)
					if engine.enableSleepTimer {
						VStack(alignment: .leading) {
							Text("Play for: \(engine.sleepTimerHours, specifier: "%.1f") hours")
							Slider(value: $engine.sleepTimerHours, in: 0.5...10, step: 0.5)
						}
						VStack(alignment: .leading) {
							Text("Fade out over: \(Int(engine.sleepFadeMinutes)) minutes")
							Slider(value: $engine.sleepFadeMinutes, in: 5...120, step: 5)
						}
					}
				}

				Section(header: Text("Morning Alarm")) {
					Toggle("Enable Morning Alarm", isOn: $engine.enableMorningAlarm)
					if engine.enableMorningAlarm {
						DatePicker("Alarm Time", selection: $engine.morningAlarmDate, displayedComponents: .hourAndMinute)
						VStack(alignment: .leading) {
							Text(engine.morningSoundscapeFadeMinutes == 0 ? "Soundscape fade in: Off" : "Soundscape fade in: \(Int(engine.morningSoundscapeFadeMinutes)) minutes")
							Slider(value: $engine.morningSoundscapeFadeMinutes, in: 0...90, step: 1)
						}
						VStack(alignment: .leading) {
							Text("Alarm Volume")
							Slider(value: $engine.alarmVolume, in: 0...1)
						}
						HStack {
							Text(engine.alarmNameStorage == "None" ? String(localized: "None") : engine.alarmNameStorage)
							Spacer()
							Menu("Alarm Sound") {
								Button("From Files") { presentFilePicker(for: .alarm) }
								Button("From Apple Music") { showingAlarmMusicPicker = true }
								if !engine.alarmPath.isEmpty {
									Button("Clear", role: .destructive) { engine.clearAlarmSound() }
								}
							}
						}
						if engine.isAlarmRinging {
							Button("Stop Alarm") { engine.stopAlarm() }
								.foregroundColor(.red)
						}
					}
				}

				Section(header: Text("Sleep Meditation")) {
					HStack {
						Text(engine.meditationNameStorage == "None" ? String(localized: "None") : engine.meditationNameStorage)
						Spacer()
						Menu("Select Meditation") {
							Button("From Files") { presentFilePicker(for: .meditation) }
							Button("From Apple Music") { showingMeditationMusicPicker = true }
							if !engine.meditationPaths.isEmpty {
								Button("Clear", role: .destructive) { engine.clearMeditation() }
							}
						}
					}
					if !engine.meditationPaths.isEmpty {
						Text("The main soundscape will automatically fade in across the duration of this meditation.")
							.font(.caption)
							.foregroundColor(.secondary)
					}
				}

				Section(header: Text("Simulation & Testing")) {
					Button("Simulate Night Fade-Out") { engine.simulateNightFadeOut() }
				}
			}
			.navigationTitle("Sleep Settings")
			.navigationBarTitleDisplayMode(.inline)
			.fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
				defer { fileImportTarget = nil }
				switch result {
				case .success(let urls):
					guard let url = urls.first, let target = fileImportTarget else { return }
					switch target {
					case .meditation:
						engine.addFile(url: url, isMeditation: true)
					case .alarm:
						engine.addAlarmFile(url: url)
					}
				case .failure(let error): print(error)
				}
			}
			.sheet(isPresented: $showingMeditationMusicPicker) {
				MediaPicker(isPresented: $showingMeditationMusicPicker) { items in
					engine.addAppleMusic(items: items.items, isMeditation: true)
				}
			}
			.sheet(isPresented: $showingAlarmMusicPicker) {
				MediaPicker(isPresented: $showingAlarmMusicPicker) { items in
					if let item = items.items.first {
						engine.addAlarmAppleMusic(item: item)
					}
				}
			}
		}
	}

	private func presentFilePicker(for target: FileImportTarget) {
		fileImportTarget = target
		DispatchQueue.main.async {
			showingFilePicker = true
		}
	}
}

struct ShareSheet: UIViewControllerRepresentable {
	var activityItems: [Any]
	var applicationActivities: [UIActivity]? = nil

	func makeUIViewController(context: Context) -> UIActivityViewController {
		UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
	}

	func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ExportView: View {
	@ObservedObject var engine: AudioEngineManager
	@Environment(\.presentationMode) var presentationMode
	
	@State private var exportType: Int = 0
	@State private var customHours: Double = 1.0
	@State private var simulatedBedtime: Date = Date()
	@State private var audioFormat: Int = 1
	@State private var isExporting: Bool = false
	@State private var exportProgress: Double = 0.0
	@State private var exportedURL: URL? = nil
	@State private var showShareSheet: Bool = false
	
	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("Export Options"), footer: Text("Exports the current soundscape configuration including rain, heartbeats, alarms, and reverb.")) {
					Picker("Duration Type", selection: $exportType) {
						Text("Custom Time").tag(0)
						Text("Night with Alarm").tag(1)
					}.pickerStyle(SegmentedPickerStyle())
					
					if exportType == 0 {
						Stepper(String(localized: "Duration: \(customHours, specifier: "%.1f") hours"), value: $customHours, in: 0.5...12.0, step: 0.5)
					} else {
						if engine.enableMorningAlarm {
							DatePicker(String(localized: "Simulated Bedtime"), selection: $simulatedBedtime, displayedComponents: .hourAndMinute)
							Text(String(localized: "Will export from this Bedtime until the Morning Alarm fires."))
								.foregroundColor(.secondary)
						} else {
							Text(String(localized: "Morning alarm is disabled. Enable it in the Alarm tab."))
								.foregroundColor(.red)
						}
					}
					
					Picker(String(localized: "Audio Quality"), selection: $audioFormat) {
						Text(String(localized: "High Quality (AAC 256 kbps)")).tag(1)
						Text(String(localized: "Lossless (ALAC)")).tag(0)
					}.pickerStyle(SegmentedPickerStyle())
				}
				
				Section {
					Button(action: startExport) {
						if isExporting {
							HStack {
								Text(String(localized: "Exporting... \(Int(exportProgress * 100))%"))
								Spacer()
								ProgressView()
							}
						} else {
							Text(audioFormat == 1 ? String(localized: "Export to .m4a (AAC)") : String(localized: "Export to .m4a (ALAC)"))
						}
					}
					.disabled(isExporting || (exportType == 1 && !engine.enableMorningAlarm))
				}
			}
			.navigationTitle("Export Soundscape")
			.navigationBarItems(trailing: Button("Done") { presentationMode.wrappedValue.dismiss() })
			.sheet(isPresented: $showShareSheet) {
				if let url = exportedURL {
					ShareSheet(activityItems: [url])
				}
			}
		}
	}
	
	private func startExport() {
		isExporting = true
		exportProgress = 0.0
		
		var duration: Double = customHours
		if exportType == 1 {
			let alarmDate = engine.morningAlarmDate
			let calendar = Calendar.current
			var nextAlarm = calendar.date(bySettingHour: calendar.component(.hour, from: alarmDate), minute: calendar.component(.minute, from: alarmDate), second: 0, of: simulatedBedtime)!
			if nextAlarm < simulatedBedtime {
				nextAlarm = calendar.date(byAdding: .day, value: 1, to: nextAlarm)!
			}
			duration = nextAlarm.timeIntervalSince(simulatedBedtime) / 3600.0
		}
		
		engine.exportSoundscape(durationHours: duration, useAAC: audioFormat == 1, simulatedStartDate: simulatedBedtime, progress: { p in
			exportProgress = p
		}) { url in
			isExporting = false
			if let url = url {
				exportedURL = url
				showShareSheet = true
			}
		}
	}
}

struct SettingsView: View {
	@ObservedObject var engine: AudioEngineManager
	@State private var showExportSheet = false
	var body: some View {
		Form {
			Section(header: Text("Export")) {
				Button("Export Soundscape...") {
					showExportSheet = true
				}
			}
			.sheet(isPresented: $showExportSheet) {
				ExportView(engine: engine)
			}

			Section(header: Text("Highly Sensitive Person (HSP) Features")) {
				Toggle("HSP Acoustic Softening", isOn: $engine.enableHSPMode)
					.accessibilityHint("Applies a global low-pass filter to muffle harsh high frequencies and soften the overall soundscape.")
				Toggle("Route Meditation through HSP EQ", isOn: $engine.meditationInHSP)
				Toggle("Deep Sleep Acoustic Dive", isOn: $engine.enableDeepSleepDive)
					.accessibilityHint("Slowly rolls off high frequencies during the fade-out, sounding like sinking underwater.")
			}

			Section(header: Text("Acoustics & Space")) {
				Picker("Room Reverb", selection: $engine.reverbIndex) {
					ForEach(0..<engine.reverbOptions.count, id: \.self) { index in
						Text(engine.reverbOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())

				Toggle("Imported Audio in Reverb Engine", isOn: $engine.importedAudioInReverb)
					.accessibilityHint("Turn off if AirPods crackle on older iOS versions.")
				Toggle("Voice Cues route through Reverb", isOn: $engine.voiceInReverb)
			}

			Section(header: Text("Breathing Audio Setup")) {
				Toggle("Use Real Breathing Recordings", isOn: $engine.useRealBreathing)
					.accessibilityHint("Replaces voice cues with real breathing recordings.")
				Toggle("Use Whispered Voice Cues", isOn: $engine.useWhisper)
			}

			Section(header: Text("Intimacy & Immersion")) {
				Toggle("Intimate Proximity Mode", isOn: $engine.enableIntimateMode)
					.accessibilityHint("Boosts proximity frequencies and simulates head-shadowing for an ASMR-like close-up feel.")
				Toggle("Haptic Heartbeat Synchronization", isOn: $engine.enableHaptics)
					.accessibilityHint("Uses the Taptic Engine to let you physically feel the heartbeat.")
				Toggle("Enhanced Vocal Anchors", isOn: $engine.enableEnhancedAnchors)
					.accessibilityHint("Spawns random spatial whispers around your head during breathing holds.")
			}

			Section(header: Text("Audio Behavior")) {
				Toggle("Mix with other apps", isOn: $engine.mixWithOthers)
					.accessibilityHint("Allows Sleep Engine to play while watching YouTube or listening to podcasts.")
				Toggle("Fade to Silent when Headphones Disconnect", isOn: $engine.fadeToSilentOnHeadphoneRemoval)
					.accessibilityHint("Fades the soundscape out over 10 seconds when headphones are removed, then keeps only the silent alarm keeper active.")
			}
		}
	}
}

struct ContentView: View {
	@StateObject var engine = AudioEngineManager()
	@State private var selectedTab = 0

	var body: some View {
		VStack(spacing: 0) {
			VStack {
				Slider(value: $engine.masterVolume, in: 0...1)
					.accessibilityLabel("Master Output Volume")
					.padding(.horizontal).padding(.top, 10)

				Button(action: {
					engine.playStop()
				}) {
					Text(engine.isAlarmRinging ? "Stop Alarm" : (engine.isPlaying ? "Stop All Audio" : "Play Master"))
						.frame(maxWidth: .infinity).padding()
						.background(engine.isPlaying ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
						.cornerRadius(10)
				}
				.padding(.horizontal).padding(.bottom, 10)
			}
			.background(Color(UIColor.secondarySystemBackground).shadow(radius: 1))

			TabView(selection: $selectedTab) {
				SoundscapeView(engine: engine)
					.tabItem { Label("Soundscape", systemImage: "waveform") }
					.tag(0)
				GeneratorView(engine: engine)
					.tabItem { Label("Generator", systemImage: "bolt.heart") }
					.tag(1)
				BreathingView(engine: engine)
					.tabItem { Label("Breathing", systemImage: "lungs") }
					.tag(2)
				SleepTimerView(engine: engine)
					.tabItem { Label("Sleep", systemImage: "moon.zzz") }
					.tag(3)
				SettingsView(engine: engine)
					.tabItem { Label("Settings", systemImage: "gear") }
					.tag(4)
			}
			.onChange(of: selectedTab) { _ in
				BeepGenerator.shared.playTabBeep()
			}
		}
		.toggleStyle(SoundToggleStyle())
	}
}

class BeepGenerator {
	static let shared = BeepGenerator()

	private var tabPlayer: AVAudioPlayer?
	private var switchPlayer: AVAudioPlayer?

	private init() {
		tabPlayer = makeTapPlayer(freq: 1200.0, duration: 0.015, volume: 0.15)
		switchPlayer = makeTapPlayer(freq: 900.0, duration: 0.015, volume: 0.12)
	}

	func playTabBeep() {
		tabPlayer?.currentTime = 0
		tabPlayer?.play()
	}

	func playSwitchBeep() {
		switchPlayer?.currentTime = 0
		switchPlayer?.play()
	}

	private func makeTapPlayer(freq: Double, duration: Double, volume: Float) -> AVAudioPlayer? {
		let sampleRate = 44100.0
		let totalSamples = Int(sampleRate * duration)

		var audioData = Data()
		audioData.append(Data("RIFF".utf8))
		let subchunk2Size = totalSamples * 2
		let chunkSize = 36 + subchunk2Size
		withUnsafeBytes(of: Int32(chunkSize)) { audioData.append(contentsOf: $0) }

		audioData.append(Data("WAVE".utf8))
		audioData.append(Data("fmt ".utf8))
		withUnsafeBytes(of: Int32(16)) { audioData.append(contentsOf: $0) }
		withUnsafeBytes(of: Int16(1)) { audioData.append(contentsOf: $0) }
		withUnsafeBytes(of: Int16(1)) { audioData.append(contentsOf: $0) }
		withUnsafeBytes(of: Int32(sampleRate)) { audioData.append(contentsOf: $0) }
		withUnsafeBytes(of: Int32(Int(sampleRate) * 2)) { audioData.append(contentsOf: $0) }
		withUnsafeBytes(of: Int16(2)) { audioData.append(contentsOf: $0) }
		withUnsafeBytes(of: Int16(16)) { audioData.append(contentsOf: $0) }

		audioData.append(Data("data".utf8))
		withUnsafeBytes(of: Int32(subchunk2Size)) { audioData.append(contentsOf: $0) }

		for i in 0..<totalSamples {
			let t = Double(i) / sampleRate

			// Very short attack, extreme exponential decay for an "ultra-gentle click"
			let attack = 0.001
			var env = 1.0
			if t < attack {
				env = t / attack
			} else {
				env = exp(-250.0 * (t - attack))
			}
			
			// A short high-frequency blip is perceived as a tiny click, much gentler than noise
			let blip = sin(2.0 * Double.pi * freq * t)

			let amplitude = 32767.0 * Double(volume)
			let sampleVal = Int16(blip * env * amplitude)
			withUnsafeBytes(of: sampleVal) { audioData.append(contentsOf: $0) }
		}

		do {
			let player = try AVAudioPlayer(data: audioData)
			player.prepareToPlay()
			return player
		} catch {
			return nil
		}
	}
}

class BiQuadFilter {
	var b0: Double = 1.0, b1: Double = 0.0, b2: Double = 0.0
	var a1: Double = 0.0, a2: Double = 0.0
	var x1: Double = 0.0, x2: Double = 0.0
	var y1: Double = 0.0, y2: Double = 0.0

	func setLowpass(frequency: Double, Q: Double, sampleRate: Double) {
		let w0 = 2.0 * Double.pi * frequency / sampleRate
		let alpha = sin(w0) / (2.0 * Q)
		let cosW0 = cos(w0)
		let a0 = 1.0 + alpha
		b0 = (1.0 - cosW0) / 2.0 / a0
		b1 = (1.0 - cosW0) / a0
		b2 = (1.0 - cosW0) / 2.0 / a0
		a1 = -2.0 * cosW0 / a0
		a2 = (1.0 - alpha) / a0
	}

	func setBandpass(frequency: Double, Q: Double, sampleRate: Double) {
		let w0 = 2.0 * Double.pi * frequency / sampleRate
		let alpha = sin(w0) / (2.0 * Q)
		let cosW0 = cos(w0)
		let a0 = 1.0 + alpha
		b0 = alpha / a0
		b1 = 0.0
		b2 = -alpha / a0
		a1 = -2.0 * cosW0 / a0
		a2 = (1.0 - alpha) / a0
	}

	func process(_ x: Double) -> Double {
		let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y
	}
}

struct SoundToggleStyle: ToggleStyle {
	func makeBody(configuration: Configuration) -> some View {
		Toggle(configuration)
			.toggleStyle(.switch)
			.onChange(of: configuration.isOn) { _ in
				BeepGenerator.shared.playSwitchBeep()
			}
	}
}

@main
struct SleepEngineApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
	}
}