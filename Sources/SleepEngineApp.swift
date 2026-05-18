// Sources/SleepEngineApp.swift
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
			avPlayer?.setVolume(avVol, fadeDuration: 0.1)
		}
		
		if enginePlayerNode != nil {
			let engineVol = Float(volume * masterVolume) * Float(specificMultiplier)
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
	var clockVolume: Float = 0
	var brownVolume: Float = 0
	var breathVolume: Float = 0
	var clickVolume: Float = 0
	var panHeartIndex: Int = 0
	var panClockIndex: Int = 0
	var panBrownIndex: Int = 0
	var panBreathIndex: Int = 0
	var panClickIndex: Int = 0
	var clockTypeIndex: Int = 0
	var syncClock: Bool = false
	var syncClick: Bool = true
	var enableSlowdown: Bool = false
	var targetBPM: Double = 40.0
	var slowdownMinutes: Double = 30.0
	var syncBreathing: Bool = false
	var useRealBreathing: Bool = true
	var isBreathing: Bool = false
	var manualBreathState: Int = 0
	var soundscapeMultiplier: Float = 1.0
	var isPlaying: Bool = false
}

class AudioEngineManager: ObservableObject {
	let engine = AVAudioEngine()
	var sourceNode: AVAudioSourceNode?
	let reverbNode = AVAudioUnitReverb()
	let preReverbMixer = AVAudioMixerNode()
	let importedMixer = AVAudioMixerNode()
	let alarmMixer = AVAudioMixerNode()
	
	let breathingNode = AVAudioPlayerNode()
	let anchorNode = AVAudioPlayerNode()
	let alarmNode = AVAudioPlayerNode()
	
	var rainPlayer: AVAudioPlayer?
	var organicHeartbeatPlayer: AVAudioPlayer?
	var silentLoopPlayer: AVAudioPlayer?
	var meditationPlayers: [AVAudioPlayer] = []
	
	var hapticEngine: CHHapticEngine?
	
	@Published var isPlaying = false { didSet { syncRenderState() } }
	@Published var isAlarmRinging = false
	@Published var importedTracks: [ImportedTrack] = []
	
	var dynamicVolumeMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	var meditationFadeMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	var postMeditationMultiplier: Double = 1.0 { didSet { updateVolumes() } }
	
	let profiles: [HeartbeatProfile] = [
		HeartbeatProfile(name: "ASMR Blood Flow (60 BPM)", bpm: 60, lubBase: 40, lubDrop: 15, lubDecay: 18, dubBase: 50, dubDrop: 20, dubDecay: 22, dubDelay: 0.30, subFreq: 35, subVol: 0.25, subDecay: 6, whooshVol: 0.50, noiseLpf: 450),
		HeartbeatProfile(name: "Standard Resting Heart (72 BPM)", bpm: 72, lubBase: 45, lubDrop: 10, lubDecay: 20, dubBase: 55, dubDrop: 15, dubDecay: 25, dubDelay: 0.28, subFreq: 30, subVol: 0.30, subDecay: 5, whooshVol: 0.30, noiseLpf: 500),
		HeartbeatProfile(name: "Womb Simulation (55 BPM)", bpm: 55, lubBase: 55, lubDrop: 20, lubDecay: 20, dubBase: 70, dubDrop: 25, dubDecay: 25, dubDelay: 0.35, subFreq: 35, subVol: 0.45, subDecay: 5, whooshVol: 0.60, noiseLpf: 650),
		HeartbeatProfile(name: "Zen Meditation (50 BPM)", bpm: 50, lubBase: 35, lubDrop: 25, lubDecay: 15, dubBase: 45, dubDrop: 30, dubDecay: 18, dubDelay: 0.32, subFreq: 30, subVol: 0.40, subDecay: 4, whooshVol: 0.12, noiseLpf: 150),
		HeartbeatProfile(name: "Athletic Recovery (45 BPM)", bpm: 45, lubBase: 40, lubDrop: 15, lubDecay: 16, dubBase: 50, dubDrop: 20, dubDecay: 20, dubDelay: 0.34, subFreq: 30, subVol: 0.50, subDecay: 5, whooshVol: 0.25, noiseLpf: 300),
		HeartbeatProfile(name: "Gentle Drift (42 BPM)", bpm: 42, lubBase: 32, lubDrop: 18, lubDecay: 14, dubBase: 38, dubDrop: 22, dubDecay: 16, dubDelay: 0.36, subFreq: 26, subVol: 0.55, subDecay: 4, whooshVol: 0.22, noiseLpf: 220),
		HeartbeatProfile(name: "Deep Sleep Resonance (40 BPM)", bpm: 40, lubBase: 30, lubDrop: 20, lubDecay: 12, dubBase: 35, dubDrop: 25, dubDecay: 15, dubDelay: 0.38, subFreq: 25, subVol: 0.60, subDecay: 4, whooshVol: 0.20, noiseLpf: 200),
		HeartbeatProfile(name: "Hibernation State (35 BPM)", bpm: 35, lubBase: 28, lubDrop: 20, lubDecay: 10, dubBase: 32, dubDrop: 25, dubDecay: 12, dubDelay: 0.40, subFreq: 22, subVol: 0.70, subDecay: 3, whooshVol: 0.15, noiseLpf: 180),
		HeartbeatProfile(name: "Deep Trance (30 BPM)", bpm: 30, lubBase: 25, lubDrop: 25, lubDecay: 10, dubBase: 30, dubDrop: 30, dubDecay: 12, dubDelay: 0.45, subFreq: 20, subVol: 0.75, subDecay: 3, whooshVol: 0.15, noiseLpf: 150),
		HeartbeatProfile(name: "Slow Wave Sleep (25 BPM)", bpm: 25, lubBase: 22, lubDrop: 25, lubDecay: 8, dubBase: 26, dubDrop: 30, dubDecay: 10, dubDelay: 0.50, subFreq: 18, subVol: 0.85, subDecay: 2, whooshVol: 0.10, noiseLpf: 130),
		HeartbeatProfile(name: "Cinematic Oceanic (18 BPM)", bpm: 18, lubBase: 25, lubDrop: 30, lubDecay: 8, dubBase: 30, dubDrop: 35, dubDecay: 10, dubDelay: 0.60, subFreq: 20, subVol: 0.90, subDecay: 2, whooshVol: 0.15, noiseLpf: 120),
		HeartbeatProfile(name: "Soft Pillowy Pulse (62 BPM)", bpm: 62, lubBase: 40, lubDrop: 15, lubDecay: 25, dubBase: 50, dubDrop: 20, dubDecay: 30, dubDelay: 0.28, subFreq: 32, subVol: 0.35, subDecay: 6, whooshVol: 0.20, noiseLpf: 250)
	]
	
	let panOptions = ["Center", "Left", "Right", "Soft Left", "Soft Right", "1 Minute Slow Shift", "5 Minute Slow Shift"]
	let clockOptions = ["Quartz Wall Clock", "Pocket Watch", "Grandfather Clock", "Metronome"]
	let placementOptions = ["Center Beats & Flow", "Lub Left Ear / Dub Right Ear", "Lub Right Ear / Dub Left Ear"]
	let anchors = ["DRIFTING", "LETTING_GO", "DEEPER", "RELAX"]
	let reverbOptions = ["Dry / No Reverb", "Small Room", "Medium Hall", "Large Hall", "Cathedral"]
	
	private var renderState = AudioRenderState()
	
	@Published var selectedProfileIndex: Int { didSet { save("selectedProfileIndex", selectedProfileIndex); resetDynamicBPM(); rebuildPrototypes(); updateNowPlaying(); syncRenderState() } }
	@Published var placementIndex: Int { didSet { save("placementIndex", placementIndex); rebuildPrototypes(); syncRenderState() } }
	@Published var masterVolume: Double { didSet { save("masterVolume", masterVolume); updateVolumes() } }
	
	@Published var heartbeatVolume: Double { didSet { save("heartbeatVolume", heartbeatVolume); syncRenderState() } }
	@Published var clockVolume: Double { didSet { save("clockVolume", clockVolume); syncRenderState() } }
	@Published var brownVolume: Double { didSet { save("brownVolume", brownVolume); syncRenderState() } }
	@Published var breathVolume: Double { didSet { save("breathVolume", breathVolume); syncRenderState() } }
	@Published var clickVolume: Double { didSet { save("clickVolume", clickVolume); syncRenderState() } }
	
	@Published var rainVolume: Double { didSet { save("rainVolume", rainVolume); updateVolumes() } }
	@Published var organicHeartbeatVolume: Double { didSet { save("organicHeartbeatVolume", organicHeartbeatVolume); updateVolumes() } }
	
	@Published var panHeartIndex: Int { didSet { save("panHeartIndex", panHeartIndex); syncRenderState() } }
	@Published var panClockIndex: Int { didSet { save("panClockIndex", panClockIndex); syncRenderState() } }
	@Published var panBrownIndex: Int { didSet { save("panBrownIndex", panBrownIndex); syncRenderState() } }
	@Published var panBreathIndex: Int { didSet { save("panBreathIndex", panBreathIndex); syncRenderState() } }
	@Published var panClickIndex: Int { didSet { save("panClickIndex", panClickIndex); syncRenderState() } }
	
	@Published var clockTypeIndex: Int { didSet { save("clockTypeIndex", clockTypeIndex); rebuildPrototypes(); syncRenderState() } }
	@Published var syncClock: Bool { didSet { save("syncClock", syncClock); syncRenderState() } }
	@Published var syncClick: Bool { didSet { save("syncClick", syncClick); syncRenderState() } }
	
	@Published var mixWithOthers: Bool { didSet { save("mixWithOthers", mixWithOthers); applyAudioSessionSettings() } }
	@Published var useWhisper: Bool { didSet { save("useWhisper", useWhisper) } }
	@Published var useRealBreathing: Bool { didSet { save("useRealBreathing", useRealBreathing); syncRenderState() } }
	
	@Published var enableHaptics: Bool { didSet { save("enableHaptics", enableHaptics) } }
	@Published var enableEnhancedAnchors: Bool { didSet { save("enableEnhancedAnchors", enableEnhancedAnchors) } }
	@Published var reverbIndex: Int { didSet { save("reverbIndex", reverbIndex); updateReverb() } }
	@Published var alarmInReverb: Bool { didSet { save("alarmInReverb", alarmInReverb); loadAlarmTrack() } }
	@Published var voiceInReverb: Bool { didSet { save("voiceInReverb", voiceInReverb); updateVoiceRouting() } }
	@Published var importedAudioInReverb: Bool { didSet { save("importedAudioInReverb", importedAudioInReverb); reloadImportedTracksRouting() } }
	
	@Published var enableSlowdown: Bool { didSet { save("enableSlowdown", enableSlowdown); syncRenderState() } }
	@Published var targetBPM: Double { didSet { save("targetBPM", targetBPM); syncRenderState() } }
	@Published var slowdownMinutes: Double { didSet { save("slowdownMinutes", slowdownMinutes); syncRenderState() } }
	
	@Published var syncBreathing: Bool { didSet { save("syncBreathing", syncBreathing); syncRenderState() } }
	@Published var isBreathing: Bool = false { didSet { syncRenderState() } }
	@Published var manualBreathState: Int = 0 { didSet { syncRenderState() } }
	
	@Published var savedTracksJSON: Data { didSet { save("savedTracksJSON", savedTracksJSON) } }
	
	@Published var enableSleepTimer: Bool { didSet { save("enableSleepTimer", enableSleepTimer) } }
	@Published var sleepTimerHours: Double { didSet { save("sleepTimerHours", sleepTimerHours) } }
	@Published var sleepFadeMinutes: Double { didSet { save("sleepFadeMinutes", sleepFadeMinutes) } }
	
	@Published var enableMorningFadeIn: Bool { didSet { save("enableMorningFadeIn", enableMorningFadeIn) } }
	@Published var morningFadeInMinutes: Double { didSet { save("morningFadeInMinutes", morningFadeInMinutes) } }
	
	var sleepTimerStartDate: Date?
	var isMorningFadeActive = false
	
	@Published var alarmTimeRef: Double { didSet { save("alarmTimeRef", alarmTimeRef) } }
	@Published var alarmTime: Date { didSet { alarmTimeRef = alarmTime.timeIntervalSince1970 } }
	@Published var isAlarmOn: Bool { didSet { save("isAlarmOn", isAlarmOn); toggleSilentBackgroundLoop() } }
	
	@Published var alarmTrackPath: String { didSet { save("alarmTrackPath", alarmTrackPath) } }
	@Published var alarmTrackIsAppleMusic: Bool { didSet { save("alarmTrackIsAppleMusic", alarmTrackIsAppleMusic) } }
	@Published var alarmTrackNameStorage: String { didSet { save("alarmTrackNameStorage", alarmTrackNameStorage) } }
	var alarmAvPlayer: AVAudioPlayer?
	
	@Published var meditationPaths: [String] { didSet { save("meditationPaths", meditationPaths) } }
	@Published var meditationIsAppleMusic: Bool { didSet { save("meditationIsAppleMusic", meditationIsAppleMusic) } }
	@Published var meditationNameStorage: String { didSet { save("meditationNameStorage", meditationNameStorage) } }
	
	var isMeditationActive = false
	var postMeditationPhase = false
	var meditationTotalDuration: TimeInterval = 0
	var meditationElapsedTime: TimeInterval = 0
	var postMeditationTime: TimeInterval = 0
	var currentMeditationIndex = 0
	
	var alarmTimer: Timer?
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
	private var breathL = [Float]()
	private var breathR = [Float]()
	private var whooshL = [Float]()
	private var whooshR = [Float]()
	private var clk = [Float]()
	
	private var realInhaleBuffer = [Float]()
	private var realExhaleBuffer = [Float]()
	private var clickBuffer = [Float]()
	
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
	
	private var smoothedVHeart: Float = 0.0
	private var smoothedVClock: Float = 0.0
	private var smoothedVBrown: Float = 0.0
	private var smoothedVBreath: Float = 0.0
	private var smoothedVClick: Float = 0.0
	
	private var breathFrameCounter: Int = 0
	private var lastManualState: Int = 0
	private var lastPhaseBeat: Int = -1
	
	private var breathingTask: Task<Void, Never>?
	private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
	@Published var currentBreathingPhase: String = "Ready"
	
	init() {
		let ud = UserDefaults.standard
		self.selectedProfileIndex = ud.integer(forKey: "selectedProfileIndex")
		self.placementIndex = ud.integer(forKey: "placementIndex")
		self.masterVolume = ud.object(forKey: "masterVolume") == nil ? 1.0 : ud.double(forKey: "masterVolume")
		
		self.heartbeatVolume = ud.double(forKey: "heartbeatVolume")
		self.clockVolume = ud.double(forKey: "clockVolume")
		self.brownVolume = ud.double(forKey: "brownVolume")
		self.breathVolume = ud.double(forKey: "breathVolume")
		self.clickVolume = ud.double(forKey: "clickVolume")
		self.rainVolume = ud.double(forKey: "rainVolume")
		self.organicHeartbeatVolume = ud.double(forKey: "organicHeartbeatVolume")
		
		self.panHeartIndex = ud.integer(forKey: "panHeartIndex")
		self.panClockIndex = ud.integer(forKey: "panClockIndex")
		self.panBrownIndex = ud.integer(forKey: "panBrownIndex")
		self.panBreathIndex = ud.integer(forKey: "panBreathIndex")
		self.panClickIndex = ud.integer(forKey: "panClickIndex")
		
		self.clockTypeIndex = ud.integer(forKey: "clockTypeIndex")
		self.syncClock = ud.bool(forKey: "syncClock")
		self.syncClick = ud.object(forKey: "syncClick") == nil ? true : ud.bool(forKey: "syncClick")
		self.mixWithOthers = ud.bool(forKey: "mixWithOthers")
		self.useWhisper = ud.bool(forKey: "useWhisper")
		self.useRealBreathing = ud.object(forKey: "useRealBreathing") == nil ? true : ud.bool(forKey: "useRealBreathing")
		
		self.enableHaptics = ud.bool(forKey: "enableHaptics")
		self.enableEnhancedAnchors = ud.bool(forKey: "enableEnhancedAnchors")
		self.reverbIndex = ud.integer(forKey: "reverbIndex")
		self.alarmInReverb = ud.object(forKey: "alarmInReverb") == nil ? false : ud.bool(forKey: "alarmInReverb")
		self.voiceInReverb = ud.object(forKey: "voiceInReverb") == nil ? false : ud.bool(forKey: "voiceInReverb")
		self.importedAudioInReverb = ud.object(forKey: "importedAudioInReverb") == nil ? false : ud.bool(forKey: "importedAudioInReverb")
		
		self.enableSlowdown = ud.bool(forKey: "enableSlowdown")
		self.targetBPM = ud.object(forKey: "targetBPM") == nil ? 40.0 : ud.double(forKey: "targetBPM")
		self.slowdownMinutes = ud.object(forKey: "slowdownMinutes") == nil ? 30.0 : ud.double(forKey: "slowdownMinutes")
		
		self.syncBreathing = ud.bool(forKey: "syncBreathing")
		self.savedTracksJSON = ud.data(forKey: "savedTracksJSON") ?? Data()
		
		self.enableSleepTimer = ud.bool(forKey: "enableSleepTimer")
		self.sleepTimerHours = ud.object(forKey: "sleepTimerHours") == nil ? 3.0 : ud.double(forKey: "sleepTimerHours")
		self.sleepFadeMinutes = ud.object(forKey: "sleepFadeMinutes") == nil ? 45.0 : ud.double(forKey: "sleepFadeMinutes")
		
		self.enableMorningFadeIn = ud.bool(forKey: "enableMorningFadeIn")
		self.morningFadeInMinutes = ud.object(forKey: "morningFadeInMinutes") == nil ? 30.0 : ud.double(forKey: "morningFadeInMinutes")
		
		self.alarmTimeRef = ud.object(forKey: "alarmTimeRef") == nil ? Date().timeIntervalSince1970 : ud.double(forKey: "alarmTimeRef")
		self.alarmTime = Date(timeIntervalSince1970: ud.object(forKey: "alarmTimeRef") as? Double ?? Date().timeIntervalSince1970)
		self.isAlarmOn = ud.bool(forKey: "isAlarmOn")
		
		self.alarmTrackPath = ud.string(forKey: "alarmTrackPath") ?? ""
		self.alarmTrackIsAppleMusic = ud.bool(forKey: "alarmTrackIsAppleMusic")
		self.alarmTrackNameStorage = ud.string(forKey: "alarmTrackNameStorage") ?? "None"
		
		self.meditationPaths = ud.stringArray(forKey: "meditationPaths") ?? []
		self.meditationIsAppleMusic = ud.bool(forKey: "meditationIsAppleMusic")
		self.meditationNameStorage = ud.string(forKey: "meditationNameStorage") ?? "None"
		
		syncRenderState()
		generateSilentWavIfNeeded()
		applyAudioSessionSettings()
		setupOrganicPlayers()
		
		realInhaleBuffer = loadWAV(filename: "REAL_INHALE")
		realExhaleBuffer = loadWAV(filename: "REAL_EXHALE")
		clickBuffer = loadWAV(filename: "CLICK")
		
		setupAudio()
		
		loadTracks()
		loadAlarmTrack()
		loadMeditationTracks()
		setupMediaControls()
		setupObservers()
		setupCoreHaptics()
		resetDynamicBPM()
		rebuildPrototypes()
		updateVolumes()
		startTimersMonitor()
		toggleSilentBackgroundLoop()
	}
	
	private func save(_ key: String, _ value: Any) {
		UserDefaults.standard.set(value, forKey: key)
	}
	
	private func syncRenderState() {
		var newState = AudioRenderState()
		newState.selectedProfileIndex = self.selectedProfileIndex
		newState.placementIndex = self.placementIndex
		newState.heartbeatVolume = Float(self.heartbeatVolume)
		newState.clockVolume = Float(self.clockVolume)
		newState.brownVolume = Float(self.brownVolume)
		newState.breathVolume = Float(self.breathVolume)
		newState.clickVolume = Float(self.clickVolume)
		newState.panHeartIndex = self.panHeartIndex
		newState.panClockIndex = self.panClockIndex
		newState.panBrownIndex = self.panBrownIndex
		newState.panBreathIndex = self.panBreathIndex
		newState.panClickIndex = self.panClickIndex
		newState.clockTypeIndex = self.clockTypeIndex
		newState.syncClock = self.syncClock
		newState.syncClick = self.syncClick
		newState.enableSlowdown = self.enableSlowdown
		newState.targetBPM = self.targetBPM
		newState.slowdownMinutes = self.slowdownMinutes
		newState.syncBreathing = self.syncBreathing
		newState.useRealBreathing = self.useRealBreathing
		newState.isBreathing = self.isBreathing
		newState.manualBreathState = self.manualBreathState
		newState.soundscapeMultiplier = Float(self.dynamicVolumeMultiplier * self.meditationFadeMultiplier)
		newState.isPlaying = self.isPlaying
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
	
	func updateReverb() {
		switch reverbIndex {
		case 1:
			reverbNode.loadFactoryPreset(.smallRoom)
			reverbNode.wetDryMix = 30
		case 2:
			reverbNode.loadFactoryPreset(.mediumHall)
			reverbNode.wetDryMix = 40
		case 3:
			reverbNode.loadFactoryPreset(.largeRoom)
			reverbNode.wetDryMix = 50
		case 4:
			reverbNode.loadFactoryPreset(.cathedral)
			reverbNode.wetDryMix = 60
		default:
			reverbNode.wetDryMix = 0
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
			engine.connect(breathingNode, to: engine.mainMixerNode, format: format)
			engine.connect(anchorNode, to: engine.mainMixerNode, format: format)
		}
	}
	
	private func updateVolumes() {
		let soundscapeMultiplier = Float(dynamicVolumeMultiplier * meditationFadeMultiplier)
		
		engine.mainMixerNode.outputVolume = Float(masterVolume)
		
		rainPlayer?.setVolume(Float(rainVolume * masterVolume) * soundscapeMultiplier, fadeDuration: 0.1)
		organicHeartbeatPlayer?.setVolume(Float(organicHeartbeatVolume * masterVolume) * soundscapeMultiplier, fadeDuration: 0.1)
		
		importedMixer.outputVolume = Float(dynamicVolumeMultiplier)
		
		let baseVoiceVol = Float(masterVolume) * soundscapeMultiplier
		breathingNode.volume = baseVoiceVol
		anchorNode.volume = baseVoiceVol * 2.0
		
		for track in importedTracks {
			track.masterVolume = masterVolume
			track.dynamicVolumeMultiplier = dynamicVolumeMultiplier
			track.meditationFadeMultiplier = meditationFadeMultiplier
			track.postMeditationMultiplier = postMeditationMultiplier
		}
		
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
		smoothedVHeart = 0.0
		smoothedVClock = 0.0
		smoothedVBrown = 0.0
		smoothedVBreath = 0.0
		smoothedVClick = 0.0
		breathFrameCounter = 0
		lastManualState = 0
		lastPhaseBeat = -1
	}
	
	private func generateSilentWavIfNeeded() {
		let fm = FileManager.default
		let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let fileURL = docs.appendingPathComponent("silence.wav")
		guard !fm.fileExists(atPath: fileURL.path) else { return }
		do {
			let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 2)!
			let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
			guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(44100 * 2)) else { return }
			buffer.frameLength = AVAudioFrameCount(44100 * 2)
			for channel in 0..<Int(format.channelCount) {
				let ptr = buffer.floatChannelData?[channel]
				for frame in 0..<Int(buffer.frameLength) { ptr?[frame] = 0.0 }
			}
			try file.write(from: buffer)
		} catch {}
	}
	
	private func toggleSilentBackgroundLoop() {
		if isAlarmOn {
			if silentLoopPlayer == nil {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let fileURL = docs.appendingPathComponent("silence.wav")
				silentLoopPlayer = try? AVAudioPlayer(contentsOf: fileURL)
				silentLoopPlayer?.numberOfLoops = -1
				silentLoopPlayer?.volume = 0.01
			}
			silentLoopPlayer?.play()
		} else {
			silentLoopPlayer?.stop()
		}
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
		rainPlayer = loadPlayer(filename: "RAIN")
		organicHeartbeatPlayer = loadPlayer(filename: "HEARTBEAT")
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
	
	func addFile(url: URL, isAlarm: Bool = false, isMeditation: Bool = false) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		let fm = FileManager.default
		let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let filename = UUID().uuidString + "-" + url.lastPathComponent
		let dest = docs.appendingPathComponent(filename)
		do {
			try fm.copyItem(at: url, to: dest)
			if isAlarm {
				alarmTrackPath = filename
				alarmTrackIsAppleMusic = false
				alarmTrackNameStorage = url.lastPathComponent
				loadAlarmTrack()
			} else if isMeditation {
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
	
	func addAppleMusic(items: [MPMediaItem], isAlarm: Bool = false, isMeditation: Bool = false) {
		if isAlarm, let first = items.first {
			alarmTrackPath = String(first.persistentID)
			alarmTrackIsAppleMusic = true
			alarmTrackNameStorage = first.title ?? "Unknown Track"
			loadAlarmTrack()
		} else if isMeditation {
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
		meditationPlayers.forEach { $0.stop() }
		meditationPlayers.removeAll()
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
	
	private func loadAlarmTrack() {
		guard !alarmTrackPath.isEmpty else { return }
		
		alarmAvPlayer?.stop()
		alarmNode.stop()
		if alarmNode.engine != nil {
			engine.disconnectNodeOutput(alarmNode)
		}
		
		var targetURL: URL?
		if alarmTrackIsAppleMusic {
			if let pid = UInt64(alarmTrackPath) {
				let query = MPMediaQuery.songs()
				let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
				query.addFilterPredicate(predicate)
				targetURL = query.items?.first?.assetURL
			}
		} else {
			let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			targetURL = docs.appendingPathComponent(alarmTrackPath)
		}
		
		guard let url = targetURL else { return }
		
		if alarmInReverb && !alarmTrackIsAppleMusic {
			if let file = try? AVAudioFile(forReading: url) {
				if alarmNode.engine == nil {
					engine.attach(alarmNode)
				}
				engine.connect(alarmNode, to: alarmMixer, format: file.processingFormat)
				alarmNode.scheduleFile(file, at: nil) { [weak self] in
					self?.loopAlarmNode(file: file)
				}
			}
		} else {
			alarmAvPlayer = try? AVAudioPlayer(contentsOf: url)
			alarmAvPlayer?.numberOfLoops = -1
			alarmAvPlayer?.prepareToPlay()
		}
	}
	
	private func loopAlarmNode(file: AVAudioFile) {
		if isAlarmRinging {
			alarmNode.scheduleFile(file, at: nil) { [weak self] in
				self?.loopAlarmNode(file: file)
			}
		}
	}
	
	private func loadMeditationTracks() {
		meditationPlayers.forEach { $0.stop() }
		meditationPlayers.removeAll()
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
			if let url = targetURL, let player = try? AVAudioPlayer(contentsOf: url) {
				player.numberOfLoops = 0
				player.prepareToPlay()
				meditationTotalDuration += player.duration
				meditationPlayers.append(player)
			}
		}
	}
	
	private func startTimersMonitor() {
		alarmTimer?.invalidate()
		alarmTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			self?.checkTimers()
		}
	}
	
	private func checkTimers() {
		let now = Date()
		let cal = Calendar.current
		
		if isPlaying && isMeditationActive && !meditationPlayers.isEmpty {
			let player = meditationPlayers[currentMeditationIndex]
			if player.isPlaying {
				meditationElapsedTime += 1.0
				meditationFadeMultiplier = min(1.0, meditationElapsedTime / max(1.0, meditationTotalDuration))
			} else {
				currentMeditationIndex += 1
				if currentMeditationIndex < meditationPlayers.count {
					meditationPlayers[currentMeditationIndex].play()
				} else {
					isMeditationActive = false
					postMeditationPhase = true
					postMeditationTime = 0
					meditationFadeMultiplier = 1.0
				}
			}
		} else if isPlaying && postMeditationPhase {
			postMeditationTime += 1.0
			postMeditationMultiplier = min(1.0, postMeditationTime / 300.0)
			if postMeditationTime >= 300.0 {
				postMeditationPhase = false
			}
		}
		
		if enableSleepTimer, let start = sleepTimerStartDate, isPlaying, !isMorningFadeActive {
			let elapsed = now.timeIntervalSince(start)
			let playTime = sleepTimerHours * 3600.0
			let fadeTime = sleepFadeMinutes * 60.0
			
			if elapsed >= playTime + fadeTime {
				dynamicVolumeMultiplier = 0.0
				stopSoundscape(keepEngineAlive: false)
			} else if elapsed >= playTime {
				dynamicVolumeMultiplier = 1.0 - ((elapsed - playTime) / fadeTime)
			} else {
				dynamicVolumeMultiplier = 1.0
			}
		}
		
		guard isAlarmOn else {
			isMorningFadeActive = false
			return
		}
		
		let nowHr = cal.component(.hour, from: now)
		let nowMin = cal.component(.minute, from: now)
		let nowSec = cal.component(.second, from: now)
		let alHr = cal.component(.hour, from: alarmTime)
		let alMin = cal.component(.minute, from: alarmTime)
		
		if nowHr == alHr && nowMin == alMin && nowSec == 0 {
			isMorningFadeActive = false
			triggerAlarm(fadeDuration: 60.0)
		} else if enableMorningFadeIn {
			var todayAlarm = cal.date(bySettingHour: alHr, minute: alMin, second: 0, of: now)!
			if todayAlarm < now { todayAlarm = cal.date(byAdding: .day, value: 1, to: todayAlarm)! }
			let timeUntilAlarm = todayAlarm.timeIntervalSince(now)
			let fadeWindow = morningFadeInMinutes * 60.0
			
			if timeUntilAlarm <= fadeWindow && timeUntilAlarm > 1.0 {
				if !isPlaying {
					dynamicVolumeMultiplier = 0.0
					isMorningFadeActive = true
					sleepTimerStartDate = nil
					playStop()
				}
				if isMorningFadeActive {
					dynamicVolumeMultiplier = 1.0 - (timeUntilAlarm / fadeWindow)
				}
			} else {
				isMorningFadeActive = false
			}
		} else {
			isMorningFadeActive = false
		}
	}
	
	func triggerAlarm(fadeDuration: Double = 60.0) {
		isAlarmOn = false
		isAlarmRinging = true
		do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
		
		if alarmInReverb && !alarmTrackIsAppleMusic {
			alarmMixer.outputVolume = 0.0
			alarmNode.play()
		} else {
			alarmAvPlayer?.setVolume(0.0, fadeDuration: 0)
			alarmAvPlayer?.play()
			alarmAvPlayer?.setVolume(1.0, fadeDuration: fadeDuration)
		}
		
		isMorningFadeActive = false
		var fadeStep = 0
		let totalSteps = Int(fadeDuration * 10)
		
		fadeTimer?.invalidate()
		fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
			guard let self = self else { return }
			fadeStep += 1
			let progress = Double(fadeStep) / Double(totalSteps)
			
			if self.isPlaying { self.dynamicVolumeMultiplier = 1.0 - progress }
			
			if self.alarmInReverb && !self.alarmTrackIsAppleMusic {
				self.alarmMixer.outputVolume = Float(progress)
			}
			
			if fadeStep >= totalSteps {
				timer.invalidate()
				if self.isPlaying {
					let keepAlive = self.isAlarmRinging && self.alarmInReverb && !self.alarmTrackIsAppleMusic
					self.stopSoundscape(keepEngineAlive: keepAlive)
					self.dynamicVolumeMultiplier = 1.0
				}
			}
		}
	}
	
	func stopAlarm() {
		alarmAvPlayer?.stop()
		alarmAvPlayer?.currentTime = 0
		alarmNode.stop()
		alarmMixer.outputVolume = 1.0
		isAlarmRinging = false
		fadeTimer?.invalidate()
		
		if isPlaying {
			stopSoundscape(keepEngineAlive: false)
		} else {
			engine.pause()
			if isAlarmOn { silentLoopPlayer?.play() } else { silentLoopPlayer?.stop() }
		}
	}
	
	func stopSoundscape(keepEngineAlive: Bool) {
		rainPlayer?.pause()
		organicHeartbeatPlayer?.pause()
		for track in importedTracks { track.pause() }
		meditationPlayers.forEach { $0.pause() }
		isPlaying = false
		sleepTimerStartDate = nil
		isMorningFadeActive = false
		UIAccessibility.post(notification: .announcement, argument: "Soundscape halted.")
		
		if !keepEngineAlive {
			engine.pause()
			if isAlarmOn {
				do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
				silentLoopPlayer?.play()
			} else {
				silentLoopPlayer?.stop()
			}
		}
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
			self.dynamicVolumeMultiplier = 1.0 - (Double(fadeStep) / Double(totalSteps))
			if fadeStep >= totalSteps {
				timer.invalidate()
				if self.isPlaying { self.stopSoundscape(keepEngineAlive: false) }
				self.dynamicVolumeMultiplier = 1.0
			}
		}
	}
	
	func simulateMorningFadeIn() {
		simulationTask?.cancel()
		if isPlaying { playStop() }
		dynamicVolumeMultiplier = 0.0
		isMorningFadeActive = true
		playStop() 
		var fadeStep = 0
		let totalSteps = Int(morningFadeInMinutes * 60.0 * 10)
		fadeTimer?.invalidate()
		fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
			guard let self = self else { return }
			fadeStep += 1
			self.dynamicVolumeMultiplier = Double(fadeStep) / Double(totalSteps)
			if fadeStep >= totalSteps {
				timer.invalidate()
				self.isMorningFadeActive = false
			}
		}
	}
	
	func simulateAlarmFading() {
		simulationTask?.cancel()
		if !isPlaying { playStop() }
		dynamicVolumeMultiplier = 1.0
		isMorningFadeActive = false
		let task = DispatchWorkItem { [weak self] in self?.triggerAlarm(fadeDuration: 60.0) }
		simulationTask = task
		DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: task)
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
		currentBreathingPhase = "Ready"
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
			let breathL = self.breathL; let breathR = self.breathR; let whooshL = self.whooshL; let whooshR = self.whooshR
			let clk = self.clk; let click = self.clickBuffer; let realInhale = self.realInhaleBuffer; let realExhale = self.realExhaleBuffer
			let nBeat = self.nBeat; let nNoise = self.nNoise
			let config = self.profiles[state.selectedProfileIndex]
			let placement = self.placementOptions[state.placementIndex]
			
			if nNoise == 0 || nBeat == 0 { return noErr }
			
			let targetVHeart = state.heartbeatVolume; let targetVClock = state.clockVolume
			let targetVBrown = state.brownVolume; let targetVBreath = state.breathVolume; let targetVClick = state.clickVolume
			let smoothFactor: Float = 0.005
			let dt = 1.0 / self.sampleRate
			let bpmDropRate = state.enableSlowdown ? ((self.startBPM - state.targetBPM) / (state.slowdownMinutes * 60.0 * self.sampleRate)) : 0.0
			let ptrL = ablPointer[0].mData?.assumingMemoryBound(to: Float.self)
			let ptrR = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
			
			for frame in 0..<Int(frameCount) {
				self.smoothedVHeart += (targetVHeart - self.smoothedVHeart) * smoothFactor
				self.smoothedVClock += (targetVClock - self.smoothedVClock) * smoothFactor
				self.smoothedVBrown += (targetVBrown - self.smoothedVBrown) * smoothFactor
				self.smoothedVBreath += (targetVBreath - self.smoothedVBreath) * smoothFactor
				self.smoothedVClick += (targetVClick - self.smoothedVClick) * smoothFactor
				
				let vHeart = self.smoothedVHeart; let vClock = self.smoothedVClock; let vBrown = self.smoothedVBrown
				let vBreath = self.smoothedVBreath; let vClick = self.smoothedVClick
				let totalGain = 1.0 + (vClock * 0.4) + (vBrown * 0.5) + (vBreath * 0.2) + (vClick * 0.3)

				let currentFrame = self.frameIdx + frame
				let timeInSeconds = Double(currentFrame) / self.sampleRate
				let tChunk = Float(timeInSeconds)
				
				var hL: Float = 0; var hR: Float = 0; var flowEnv: Float = 0
				var beatDuration = 60.0 / self.currentDynamicBPM
				
				if state.enableSlowdown {
					if bpmDropRate > 0 && self.currentDynamicBPM > state.targetBPM {
						self.currentDynamicBPM -= bpmDropRate
						if self.currentDynamicBPM < state.targetBPM { self.currentDynamicBPM = state.targetBPM }
					} else if bpmDropRate < 0 && self.currentDynamicBPM < state.targetBPM {
						self.currentDynamicBPM -= bpmDropRate
						if self.currentDynamicBPM > state.targetBPM { self.currentDynamicBPM = state.targetBPM }
					}
					beatDuration = 60.0 / self.currentDynamicBPM; self.tBeat += dt
					let clockType = self.clockOptions[state.clockTypeIndex]
					let ticksPerBeat = clockType == "Pocket Watch" ? 2 : 1
					
					if self.tBeat >= beatDuration {
						self.tBeat -= beatDuration; self.beatCounter += 1; self.clkPlayIdx = 0
						if state.syncClick { self.clickPlayIdx = 0 }
						DispatchQueue.main.async { self.triggerCustomHeartbeatHaptic(isLub: true) }
						if state.syncBreathing && !state.isBreathing {
							let phaseBeat = self.beatCounter % 8
							if phaseBeat != self.lastPhaseBeat {
								self.lastPhaseBeat = phaseBeat
								if phaseBeat == 0 {
									DispatchQueue.main.async { self.currentBreathingPhase = "Inhale (Sync)"; if !state.useRealBreathing { self.playBreathingCue(type: "INHALE") } }
								} else if phaseBeat == 4 {
									DispatchQueue.main.async { self.currentBreathingPhase = "Exhale (Sync)"; if !state.useRealBreathing { self.playBreathingCue(type: "EXHALE") } }
								} else if phaseBeat == 2 && self.enableEnhancedAnchors && Bool.random() {
									let anchor = self.anchors.randomElement()!
									DispatchQueue.main.async { self.playBreathingCue(type: anchor, isAnchor: true) }
								}
							}
						}
					}
					if self.tBeat >= config.dubDelay && self.tBeat - dt < config.dubDelay { DispatchQueue.main.async { self.triggerCustomHeartbeatHaptic(isLub: false) } }
					if ticksPerBeat == 2 && self.tBeat >= (beatDuration / 2.0) && self.tBeat - dt < (beatDuration / 2.0) { self.clkPlayIdx2 = 0 }
					
					let t = self.tBeat; let atk = 0.04; let rel = 0.02
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
					if placement == "Center Beats & Flow" {
						hL = (combinedLub + combinedDub) * 0.85; hR = (combinedLub + combinedDub) * 0.85
					} else if placement == "Lub Left Ear / Dub Right Ear" {
						hL = combinedLub; hR = combinedDub
					} else {
						hL = combinedDub; hR = combinedLub
					}
					flowEnv = 0.6 + 0.4 * Float(lEnv + dEnv)
				} else {
					let idxBeat = currentFrame % nBeat
					if idxBeat == 0 {
						self.beatCounter += 1; self.clkPlayIdx = 0
						if state.syncClick { self.clickPlayIdx = 0 }
						DispatchQueue.main.async { self.triggerCustomHeartbeatHaptic(isLub: true) }
						if state.syncBreathing && !state.isBreathing {
							let phaseBeat = self.beatCounter % 8
							if phaseBeat != self.lastPhaseBeat {
								self.lastPhaseBeat = phaseBeat
								if phaseBeat == 0 {
									DispatchQueue.main.async { self.currentBreathingPhase = "Inhale (Sync)"; if !state.useRealBreathing { self.playBreathingCue(type: "INHALE") } }
								} else if phaseBeat == 4 {
									DispatchQueue.main.async { self.currentBreathingPhase = "Exhale (Sync)"; if !state.useRealBreathing { self.playBreathingCue(type: "EXHALE") } }
								} else if phaseBeat == 2 && self.enableEnhancedAnchors && Bool.random() {
									let anchor = self.anchors.randomElement()!
									DispatchQueue.main.async { self.playBreathingCue(type: anchor, isAnchor: true) }
								}
							}
						}
					}
					let dubStartIdx = Int(config.dubDelay * self.sampleRate)
					if idxBeat == dubStartIdx { DispatchQueue.main.async { self.triggerCustomHeartbeatHaptic(isLub: false) } }
					let clockType = self.clockOptions[state.clockTypeIndex]
					let halfBeat = nBeat / 2
					if clockType == "Pocket Watch" && idxBeat == halfBeat { self.clkPlayIdx2 = 0 }
					hL = lubL[idxBeat] + dubL[idxBeat]; hR = lubR[idxBeat] + dubR[idxBeat]
					flowEnv = 0.6 + 0.4 * (lubEnv[idxBeat] + dubEnv[idxBeat])
				}
				
				if !state.syncClick && currentFrame % Int(self.sampleRate) == 0 { self.clickPlayIdx = 0 }
				let idxNoise = currentFrame % nNoise
				let wVol = Float(config.whooshVol)
				hL += whooshL[idxNoise] * flowEnv * wVol; hR += whooshR[idxNoise] * flowEnv * wVol
				let posH = self.getPanPos(mode: state.panHeartIndex, time: tChunk)
				let (chunkHL, chunkHR) = self.applyStereoPan(inL: hL, inR: hR, pos: posH, vol: vHeart)
				
				var chunkCL: Float = 0; var chunkCR: Float = 0
				if vClock > 0 {
					var clkWave: Float = 0
					if state.syncClock {
						if self.clkPlayIdx < clk.count { clkWave += clk[self.clkPlayIdx]; self.clkPlayIdx += 1 }
						if self.clkPlayIdx2 < clk.count { clkWave += clk[self.clkPlayIdx2]; self.clkPlayIdx2 += 1 }
					} else { clkWave = clk[currentFrame % clk.count] }
					let posC = self.getPanPos(mode: state.panClockIndex, time: tChunk)
					let pannedC = self.applyStereoPan(inL: clkWave, inR: clkWave, pos: posC, vol: vClock * 0.4)
					chunkCL = pannedC.0; chunkCR = pannedC.1
				}
				
				var chunkClickL: Float = 0; var chunkClickR: Float = 0
				if vClick > 0 && self.clickPlayIdx < click.count {
					let cSample = click[self.clickPlayIdx]
					let posClick = self.getPanPos(mode: state.panClickIndex, time: tChunk)
					let pannedClick = self.applyStereoPan(inL: cSample, inR: cSample, pos: posClick, vol: vClick * 0.8)
					chunkClickL = pannedClick.0; chunkClickR = pannedClick.1
					self.clickPlayIdx += 1
				}
				
				var chunkBL: Float = 0; var chunkBR: Float = 0
				if vBrown > 0 {
					let posB = self.getPanPos(mode: state.panBrownIndex, time: tChunk)
					let pannedB = self.applyStereoPan(inL: brownL[idxNoise], inR: brownR[idxNoise], pos: posB, vol: vBrown * 0.5)
					chunkBL = pannedB.0; chunkBR = pannedB.1
				}
				
				var chunkBrL: Float = 0; var chunkBrR: Float = 0
				if vBreath > 0 && !state.isBreathing {
					var breathEnv: Float = 0; var sampleIdxForRealBreath = 0; var usingInhale = false; var usingExhale = false
					if state.syncBreathing {
						let syncPhase: Double
						if state.enableSlowdown { syncPhase = Double(self.beatCounter % 8) + (self.tBeat / beatDuration) }
						else { let beatRatio = Double(currentFrame % nBeat) / Double(nBeat); syncPhase = Double(self.beatCounter % 8) + beatRatio }
						if syncPhase < 4.0 {
							usingInhale = true; let inhalePhase = Float(sin(Double.pi * syncPhase / 4.0)); breathEnv = inhalePhase * 0.8
							sampleIdxForRealBreath = Int((syncPhase / 4.0) * (4.0 * beatDuration * self.sampleRate))
						} else if syncPhase >= 4.0 && syncPhase < 8.0 {
							usingExhale = true; let exhalePhase = Float(sin(Double.pi * (syncPhase - 4.0) / 4.0)); breathEnv = exhalePhase * 0.6
							sampleIdxForRealBreath = Int(((syncPhase - 4.0) / 4.0) * (4.0 * beatDuration * self.sampleRate))
						}
					} else {
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
					let pannedBr = self.applyStereoPan(inL: breathSampleL * breathEnv, inR: breathSampleR * breathEnv, pos: posBr, vol: vBreath * 2.5)
					chunkBrL = pannedBr.0; chunkBrR = pannedBr.1
				}
				
				let finalL = ((chunkHL + chunkCL + chunkBL + chunkBrL + chunkClickL) / totalGain) * state.soundscapeMultiplier
				let finalR = ((chunkHR + chunkCR + chunkBR + chunkBrR + chunkClickR) / totalGain) * state.soundscapeMultiplier
				ptrL?[frame] = finalL; ptrR?[frame] = finalR
			}
			self.frameIdx += Int(frameCount)
			return noErr
		}
		
		if let node = sourceNode {
			engine.attach(node)
			engine.attach(preReverbMixer)
			engine.attach(importedMixer)
			engine.attach(alarmMixer)
			engine.attach(reverbNode)
			engine.attach(breathingNode)
			engine.attach(anchorNode)
			
			engine.connect(node, to: preReverbMixer, format: format)
			engine.connect(importedMixer, to: preReverbMixer, format: format)
			engine.connect(alarmMixer, to: preReverbMixer, format: format)
			
			engine.connect(preReverbMixer, to: reverbNode, format: format)
			engine.connect(reverbNode, to: engine.mainMixerNode, format: format)
			
			updateVoiceRouting()
			updateReverb()
		}
	}
	
	private func getPanPos(mode: Int, time: Float) -> Float {
		let option = panOptions[mode]
		switch option {
		case "Center": return 0.0
		case "Left": return -1.0
		case "Right": return 1.0
		case "Soft Left": return -0.5
		case "Soft Right": return 0.5
		default:
			var period: Float = 60.0
			if option.contains("1 Minute") { period = 60.0 }
			else if option.contains("5 Minute") { period = 300.0 }
			return sin(2.0 * Float.pi * time / period)
		}
	}
	
	private func applyStereoPan(inL: Float, inR: Float, pos: Float, vol: Float) -> (Float, Float) {
		let bleedToL = pos < 0 ? abs(pos) : 0.0
		let bleedToR = pos > 0 ? pos : 0.0
		let keepL = pos > 0 ? 1.0 - pos : 1.0
		let keepR = pos < 0 ? 1.0 - abs(pos) : 1.0
		let norm = 1.0 + abs(pos)
		let outL = ((inL * keepL + inR * bleedToL) / norm) * vol
		let outR = ((inR * keepR + inL * bleedToR) / norm) * vol
		return (outL, outR)
	}

	private func gaussianRandom() -> Float {
		var u1: Float = 0
		repeat { u1 = Float.random(in: 0..<1) } while u1 == 0
		let u2 = Float.random(in: 0..<1)
		return sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
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
		let placement = placementOptions[placementIndex]
		
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
			if placement == "Center Beats & Flow" {
				localLubL[i] = combinedLub * 0.85; localLubR[i] = combinedLub * 0.85
				localDubL[i] = combinedDub * 0.85; localDubR[i] = combinedDub * 0.85
			} else if placement == "Lub Left Ear / Dub Right Ear" {
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
		whooshL = generateSeamlessNoise(length: nNoise, lpfFreq: config.noiseLpf); whooshR = generateSeamlessNoise(length: nNoise, lpfFreq: config.noiseLpf)
		
		let clkType = clockOptions[clockTypeIndex]; let nClockProto = Int(sampleRate * 1.5)
		clk = [Float](repeating: 0, count: nClockProto)
		for i in 0..<nClockProto {
			let tc = Double(i) / sampleRate; let randomGaussian = gaussianRandom() * 0.3
			if clkType == "Quartz Wall Clock" {
				let body = (sin(2 * Double.pi * 1200 * tc) * 0.15 + sin(2 * Double.pi * 2000 * tc) * 0.05) * exp(-120 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-300 * tc))
			} else if clkType == "Pocket Watch" {
				let body = (sin(2 * Double.pi * 4000 * tc) * 0.1 + sin(2 * Double.pi * 6000 * tc) * 0.05) * exp(-200 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-800 * tc)) * 1.5
			} else if clkType == "Grandfather Clock" {
				let body = (sin(2 * Double.pi * 350 * tc) * 0.2 + sin(2 * Double.pi * 800 * tc) * 0.1) * exp(-60 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-500 * tc)) * 1.2
			} else {
				let body = (sin(2 * Double.pi * 1000 * tc) * 0.3 + sin(2 * Double.pi * 2000 * tc) * 0.1) * exp(-100 * tc)
				clk[i] = Float(body) + randomGaussian * Float(exp(-600 * tc)) * 1.2
			}
		}
	}
	
	func playStop() {
		if isPlaying {
			stopSoundscape(keepEngineAlive: false)
		} else {
			do {
				let session = AVAudioSession.sharedInstance()
				var options: AVAudioSession.CategoryOptions = []
				if mixWithOthers { options.insert(.mixWithOthers) }
				try session.setCategory(.playback, mode: .default, options: options)
				try session.setActive(true)
				
				if sourceNode == nil { setupAudio() }
				
				resetDynamicBPM()
				updateVoiceRouting()
				
				engine.prepare()
				
				if !meditationPlayers.isEmpty {
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
				}
				
				updateVolumes()
				try engine.start()
				
				if !isMorningFadeActive {
					sleepTimerStartDate = Date()
					dynamicVolumeMultiplier = 1.0
				}
				
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
					guard let self = self else { return }
					guard self.engine.isRunning else { return }
					self.rainPlayer?.play()
					self.organicHeartbeatPlayer?.play()
					for track in self.importedTracks { track.play() }
					if self.isMeditationActive && !self.meditationPlayers.isEmpty {
						self.meditationPlayers[self.currentMeditationIndex].play()
					}
					self.isPlaying = true
					self.updateNowPlaying()
					UIAccessibility.post(notification: .announcement, argument: "Audio stream active.")
				}
			} catch { print("Engine start error: \(error)") }
		}
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
			if self.isPlaying { self.playStop(); return .success }
			return .commandFailed
		}
	}
	
	private func updateNowPlaying() {
		var nowPlayingInfo = [String: Any]()
		nowPlayingInfo[MPMediaItemPropertyTitle] = profiles[selectedProfileIndex].name
		nowPlayingInfo[MPMediaItemPropertyArtist] = "Sleep Engine"
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
	}
	
	private func setupObservers() {
		NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
			guard let self = self, let userInfo = notification.userInfo,
				  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
				  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
			if type == .began {
				if self.isPlaying { self.playStop() }
				if self.isAlarmOn { 
					do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
					self.silentLoopPlayer?.play() 
				}
			} else if type == .ended {
				guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
				let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
				if options.contains(.shouldResume) { if !self.isPlaying { self.playStop() } }
			}
		}
		
		NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
			guard let self = self, let userInfo = notification.userInfo,
				  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
				  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
			if reason == .oldDeviceUnavailable {
				if self.isPlaying { self.playStop() }
				if self.isAlarmOn { 
					do { try AVAudioSession.sharedInstance().setActive(true) } catch {}
					self.silentLoopPlayer?.play() 
				}
			}
		}
		
		NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
			guard let self = self else { return }
			if self.isPlaying {
				do {
					try self.engine.start()
					self.rainPlayer?.play()
					self.organicHeartbeatPlayer?.play()
					for track in self.importedTracks { track.play() }
					if self.isMeditationActive && !self.meditationPlayers.isEmpty {
						self.meditationPlayers[self.currentMeditationIndex].play()
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
					Toggle("Sync to Heartbeat", isOn: $engine.syncClick)
				}.padding(.vertical, 4)
				
				VStack(alignment: .leading) {
					Text("Brown Noise").accessibilityHidden(true)
					Slider(value: $engine.brownVolume, in: 0...1).accessibilityLabel("Brown Noise Volume")
				}.padding(.vertical, 4)
				
				VStack(alignment: .leading) {
					Text("Slow Breathing Base").bold()
					Slider(value: $engine.breathVolume, in: 0...1).accessibilityLabel("Slow Breathing Volume")
				}.padding(.vertical, 4)
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

struct AlarmView: View {
	@ObservedObject var engine: AudioEngineManager
	@State private var showingAlarmFilePicker = false
	@State private var showingAlarmMusicPicker = false
	@State private var showingMeditationFilePicker = false
	@State private var showingMeditationMusicPicker = false
	
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
				
				Section(header: Text("Sleep Meditation")) {
					HStack {
						Text(engine.meditationNameStorage)
						Spacer()
						Menu("Select Meditation") {
							Button("From Files") { showingMeditationFilePicker = true }
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
				
				Section(header: Text("Alarm Time")) {
					DatePicker("Time", selection: $engine.alarmTime, displayedComponents: .hourAndMinute)
						.datePickerStyle(WheelDatePickerStyle())
						.accessibilityLabel("Set Alarm Time")
					Toggle("Alarm Enabled", isOn: $engine.isAlarmOn)
				}
				
				Section(header: Text("Morning Fade-In")) {
					Toggle("Enable Pre-Alarm Fade-In", isOn: $engine.enableMorningFadeIn)
					if engine.enableMorningFadeIn {
						VStack(alignment: .leading) {
							Text("Begin fading in: \(Int(engine.morningFadeInMinutes)) mins before")
							Slider(value: $engine.morningFadeInMinutes, in: 5...120, step: 5)
						}
					}
				}
				
				Section(header: Text("Alarm Track")) {
					HStack {
						Text(engine.alarmTrackNameStorage)
						Spacer()
						Menu("Select Sound") {
							Button("From Files") { showingAlarmFilePicker = true }
							Button("From Apple Music") { showingAlarmMusicPicker = true }
						}
					}
				}
				
				Section(header: Text("Simulation & Testing")) {
					Button("Simulate Night Fade-Out") { engine.simulateNightFadeOut() }
					Button("Simulate Morning Fade-In") { engine.simulateMorningFadeIn() }
					Button("Simulate Alarm Fading") { engine.simulateAlarmFading() }
				}
			}
			.navigationTitle("Schedule & Alarm")
			.navigationBarTitleDisplayMode(.inline)
			.fileImporter(isPresented: $showingAlarmFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
				switch result {
				case .success(let urls): if let url = urls.first { engine.addFile(url: url, isAlarm: true) }
				case .failure(let error): print(error)
				}
			}
			.sheet(isPresented: $showingAlarmMusicPicker) {
				MediaPicker(isPresented: $showingAlarmMusicPicker) { items in
					engine.addAppleMusic(items: items.items, isAlarm: true)
				}
			}
			.fileImporter(isPresented: $showingMeditationFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
				switch result {
				case .success(let urls): if let url = urls.first { engine.addFile(url: url, isMeditation: true) }
				case .failure(let error): print(error)
				}
			}
			.sheet(isPresented: $showingMeditationMusicPicker) {
				MediaPicker(isPresented: $showingMeditationMusicPicker) { items in
					engine.addAppleMusic(items: items.items, isMeditation: true)
				}
			}
		}
	}
}

struct SettingsView: View {
	@ObservedObject var engine: AudioEngineManager
	var body: some View {
		Form {
			Section(header: Text("Acoustics & Space")) {
				Picker("Room Reverb", selection: $engine.reverbIndex) {
					ForEach(0..<engine.reverbOptions.count, id: \.self) { index in
						Text(engine.reverbOptions[index]).tag(index)
					}
				}
				.pickerStyle(MenuPickerStyle())
				
				Toggle("Imported Audio in Reverb Engine", isOn: $engine.importedAudioInReverb)
					.accessibilityHint("Turn off if AirPods crackle on older iOS versions.")
				Toggle("Alarm routes through Reverb", isOn: $engine.alarmInReverb)
					.accessibilityHint("If disabled, alarm plays dry. Ignored for Apple Music alarm tracks.")
				Toggle("Voice Cues route through Reverb", isOn: $engine.voiceInReverb)
			}

			Section(header: Text("Breathing Audio Setup")) {
				Toggle("Use Real Breathing Recordings", isOn: $engine.useRealBreathing)
					.accessibilityHint("Replaces voice cues with real breathing recordings.")
				Toggle("Use Whispered Voice Cues", isOn: $engine.useWhisper)
			}
			
			Section(header: Text("Intimacy & Immersion")) {
				Toggle("Haptic Heartbeat Synchronization", isOn: $engine.enableHaptics)
					.accessibilityHint("Uses the Taptic Engine to let you physically feel the heartbeat.")
				Toggle("Enhanced Vocal Anchors", isOn: $engine.enableEnhancedAnchors)
					.accessibilityHint("Spawns random spatial whispers around your head during breathing holds.")
			}
			
			Section(header: Text("Audio Behavior")) {
				Toggle("Mix with other apps", isOn: $engine.mixWithOthers)
					.accessibilityHint("Allows Sleep Engine to play while watching YouTube or listening to podcasts.")
			}
		}
	}
}

struct ContentView: View {
	@StateObject var engine = AudioEngineManager()
	
	var body: some View {
		VStack(spacing: 0) {
			VStack {
				Slider(value: $engine.masterVolume, in: 0...1)
					.accessibilityLabel("Master Output Volume")
					.padding(.horizontal).padding(.top, 10)
				
				Button(action: {
					if engine.isAlarmRinging {
						engine.stopAlarm()
					} else {
						engine.playStop()
					}
				}) {
					Text(engine.isAlarmRinging ? "Stop Alarm" : (engine.isPlaying ? "Stop All Audio" : "Play Master"))
						.frame(maxWidth: .infinity).padding()
						.background(engine.isAlarmRinging ? Color.orange.opacity(0.2) : (engine.isPlaying ? Color.red.opacity(0.2) : Color.blue.opacity(0.2)))
						.cornerRadius(10)
				}
				.padding(.horizontal).padding(.bottom, 10)
			}
			.background(Color(UIColor.secondarySystemBackground).shadow(radius: 1))
			
			TabView {
				SoundscapeView(engine: engine).tabItem { Label("Soundscape", systemImage: "waveform") }
				GeneratorView(engine: engine).tabItem { Label("Generator", systemImage: "bolt.heart") }
				BreathingView(engine: engine).tabItem { Label("Breathing", systemImage: "lungs") }
				AlarmView(engine: engine).tabItem { Label("Schedule", systemImage: "alarm") }
				SettingsView(engine: engine).tabItem { Label("Settings", systemImage: "gear") }
			}
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