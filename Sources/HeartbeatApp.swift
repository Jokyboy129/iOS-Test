import SwiftUI
import AVFoundation
import MediaPlayer

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

class AudioEngineManager: ObservableObject {
	let engine = AVAudioEngine()
	var sourceNode: AVAudioSourceNode?
	
	var rainPlayer: AVAudioPlayer?
	var organicHeartbeatPlayer: AVAudioPlayer?
	var customFilePlayer: AVAudioPlayer?
	var breathingPlayer: AVAudioPlayer?
	var musicPlayer = MPMusicPlayerController.applicationQueuePlayer
	
	@Published var isPlaying = false
	
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
	let placementOptions = ["Center Beats", "Lub L / Dub R", "Lub R / Dub L"]
	
	@AppStorage("selectedProfileIndex") var selectedProfileIndex = 0 { didSet { rebuildPrototypes(); updateNowPlaying() } }
	@AppStorage("placementIndex") var placementIndex = 0 { didSet { rebuildPrototypes() } }
	
	@AppStorage("masterVolume") var masterVolume: Double = 1.0 { didSet { updateVolumes() } }
	@AppStorage("heartbeatVolume") var heartbeatVolume: Double = 1.0
	@AppStorage("clockVolume") var clockVolume: Double = 0.0
	@AppStorage("brownVolume") var brownVolume: Double = 0.0
	@AppStorage("breathVolume") var breathVolume: Double = 0.0
	@AppStorage("rainVolume") var rainVolume: Double = 0.0 { didSet { updateVolumes() } }
	@AppStorage("organicHeartbeatVolume") var organicHeartbeatVolume: Double = 0.0 { didSet { updateVolumes() } }
	@AppStorage("customFileVolume") var customFileVolume: Double = 0.5 { didSet { updateVolumes() } }
	
	@AppStorage("panHeartIndex") var panHeartIndex = 0
	@AppStorage("panClockIndex") var panClockIndex = 0
	@AppStorage("panBrownIndex") var panBrownIndex = 0
	@AppStorage("panBreathIndex") var panBreathIndex = 0
	
	@AppStorage("clockTypeIndex") var clockTypeIndex = 0 { didSet { rebuildPrototypes() } }
	@AppStorage("syncClock") var syncClock = false { didSet { rebuildPrototypes() } }
	
	@AppStorage("mixWithOthers") var mixWithOthers = false { didSet { setupAudioSession() } }
	@AppStorage("useWhisper") var useWhisper = false
	
	@AppStorage("customFileBookmark") var customFileBookmark: Data?
	@Published var customFileName: String = "None"
	
	private var lubL = [Float](); private var lubR = [Float]()
	private var dubL = [Float](); private var dubR = [Float]()
	private var lubEnv = [Float](); private var dubEnv = [Float]()
	private var brownL = [Float](); private var brownR = [Float]()
	private var breathL = [Float](); private var breathR = [Float]()
	private var whooshL = [Float](); private var whooshR = [Float]()
	private var clk = [Float]()
	
	private var nBeat = 0; private var nNoise = 0; private var nClock = 0
	private var frameIdx = 0
	private let sampleRate: Double = 44100.0
	
	private var breathingTask: Task<Void, Never>?
	@Published var currentBreathingPhase: String = "Ready"
	
	init() {
		setupAudioSession()
		setupOrganicPlayers()
		loadCustomFileFromBookmark()
		setupMediaControls()
		setupObservers()
		rebuildPrototypes()
		updateVolumes()
	}
	
	private func setupAudioSession() {
		do {
			let session = AVAudioSession.sharedInstance()
			let options: AVAudioSession.CategoryOptions = mixWithOthers ? [.mixWithOthers] : []
			try session.setCategory(.playback, mode: .default, options: options)
			try session.setPreferredSampleRate(sampleRate)
			try session.setActive(true)
		} catch {
			print("Audio Session error: \(error)")
		}
	}
	
	private func updateVolumes() {
		engine.mainMixerNode.outputVolume = Float(masterVolume)
		rainPlayer?.volume = Float(rainVolume * masterVolume)
		organicHeartbeatPlayer?.volume = Float(organicHeartbeatVolume * masterVolume)
		customFilePlayer?.volume = Float(customFileVolume * masterVolume)
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
	
	func loadCustomFile(url: URL) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		
		do {
			let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
			customFileBookmark = data
			customFileName = url.lastPathComponent
			
			customFilePlayer = try AVAudioPlayer(contentsOf: url)
			customFilePlayer?.numberOfLoops = -1
			customFilePlayer?.prepareToPlay()
			if isPlaying { customFilePlayer?.play() }
		} catch {
			print("File loading error: \(error)")
		}
	}
	
	private func loadCustomFileFromBookmark() {
		guard let data = customFileBookmark else { return }
		var isStale = false
		do {
			let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
			if isStale { customFileBookmark = nil; return }
			if url.startAccessingSecurityScopedResource() {
				customFileName = url.lastPathComponent
				customFilePlayer = try AVAudioPlayer(contentsOf: url)
				customFilePlayer?.numberOfLoops = -1
				customFilePlayer?.prepareToPlay()
			}
		} catch {
			customFileBookmark = nil
		}
	}
	
	func playBreathingCue(type: String) {
		let suffix = useWhisper ? "_WHISPER" : ""
		guard let url = Bundle.main.url(forResource: "\(type)\(suffix)", withExtension: "wav") else { return }
		do {
			breathingPlayer = try AVAudioPlayer(contentsOf: url)
			breathingPlayer?.volume = Float(masterVolume)
			breathingPlayer?.play()
		} catch {}
	}
	
	func startBreathingExercise(inhale: Int, hold1: Int, exhale: Int, hold2: Int) {
		breathingTask?.cancel()
		breathingTask = Task {
			while !Task.isCancelled {
				await MainActor.run { currentBreathingPhase = "Inhale (\(inhale)s)"; playBreathingCue(type: "INHALE") }
				try? await Task.sleep(nanoseconds: UInt64(inhale) * 1_000_000_000)
				if Task.isCancelled { break }
				
				if hold1 > 0 {
					await MainActor.run { currentBreathingPhase = "Hold (\(hold1)s)"; playBreathingCue(type: "HOLD") }
					try? await Task.sleep(nanoseconds: UInt64(hold1) * 1_000_000_000)
					if Task.isCancelled { break }
				}
				
				await MainActor.run { currentBreathingPhase = "Exhale (\(exhale)s)"; playBreathingCue(type: "EXHALE") }
				try? await Task.sleep(nanoseconds: UInt64(exhale) * 1_000_000_000)
				if Task.isCancelled { break }
				
				if hold2 > 0 {
					await MainActor.run { currentBreathingPhase = "Hold (\(hold2)s)"; playBreathingCue(type: "HOLD") }
					try? await Task.sleep(nanoseconds: UInt64(hold2) * 1_000_000_000)
				}
			}
		}
	}
	
	func stopBreathingExercise() {
		breathingTask?.cancel()
		currentBreathingPhase = "Ready"
	}

	private func setupAudio() {
		let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
		sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
			guard let self = self else { return noErr }
			let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
			
			if self.nBeat == 0 { return noErr }
			
			let vHeart = Float(self.heartbeatVolume)
			let vClock = Float(self.clockVolume)
			let vBrown = Float(self.brownVolume)
			let vBreath = Float(self.breathVolume)
			let totalGain = 1.0 + (vClock * 0.4) + (vBrown * 0.5) + (vBreath * 0.6)
			
			for frame in 0..<Int(frameCount) {
				let currentFrame = self.frameIdx + frame
				let tChunk = Float(currentFrame) / Float(self.sampleRate)
				let idxBeat = currentFrame % self.nBeat
				let idxNoise = currentFrame % self.nNoise
				let idxClock = currentFrame % self.nClock
				
				let beatL = self.lubL[idxBeat] + self.dubL[idxBeat]
				let beatR = self.lubR[idxBeat] + self.dubR[idxBeat]
				let config = self.profiles[self.selectedProfileIndex]
				
				let finalL = (beatL * vHeart) / totalGain
				let finalR = (beatR * vHeart) / totalGain
				
				let ptrL = ablPointer[0].mData?.assumingMemoryBound(to: Float.self)
				let ptrR = ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
				ptrL?[frame] = finalL
				ptrR?[frame] = finalR
			}
			self.frameIdx += Int(frameCount)
			return noErr
		}
		
		if let node = sourceNode {
			engine.attach(node)
			engine.connect(node, to: engine.mainMixerNode, format: format)
		}
	}
	
	private func getPanPos(mode: Int, time: Float) -> Float {
		let option = panOptions[mode]
		switch option {
		case "Center": return 0.0
		case "Left": return -1.0
		case "Right": return 1.0
		default: return sin(2.0 * Float.pi * time / 60.0)
		}
	}

	func playStop() {
		if isPlaying {
			engine.pause()
			rainPlayer?.pause()
			organicHeartbeatPlayer?.pause()
			customFilePlayer?.pause()
			musicPlayer.pause()
			isPlaying = false
			UIAccessibility.post(notification: .announcement, argument: "Engine halted.")
		} else {
			do {
				try AVAudioSession.sharedInstance().setActive(true)
				if sourceNode == nil { setupAudio() }
				try engine.start()
				rainPlayer?.play()
				organicHeartbeatPlayer?.play()
				customFilePlayer?.play()
				musicPlayer.play()
				isPlaying = true
				updateNowPlaying()
				UIAccessibility.post(notification: .announcement, argument: "Audio stream active.")
			} catch { print("Engine start error: \(error)") }
		}
	}
	
	private func setupMediaControls() {}
	private func updateNowPlaying() {}
	private func setupObservers() {}
	
	private func rebuildPrototypes() {
		let config = profiles[selectedProfileIndex]
		let bpm = config.bpm
		nBeat = Int((60.0 / bpm) * sampleRate)
		nNoise = Int(sampleRate * 5)
		nClock = nBeat
		
		lubL = [Float](repeating: 0, count: nBeat)
		lubR = [Float](repeating: 0, count: nBeat)
		dubL = [Float](repeating: 0, count: nBeat)
		dubR = [Float](repeating: 0, count: nBeat)
		
		for i in 0..<nBeat {
			let t = Double(i) / sampleRate
			let lubPhase = 2 * Double.pi * (config.lubBase * t)
			let lub = sin(lubPhase) * exp(-config.lubDecay * t)
			
			let placement = placementOptions[placementIndex]
			if placement == "Center Beats" {
				lubL[i] = Float(lub * 0.85); lubR[i] = Float(lub * 0.85)
			} else if placement == "Lub L / Dub R" {
				lubL[i] = Float(lub); lubR[i] = 0
			} else {
				lubL[i] = 0; lubR[i] = Float(lub)
			}
		}
	}
}

struct SoundscapeView: View {
	@ObservedObject var engine: AudioEngineManager
	@State private var showingFilePicker = false
	
	var body: some View {
		Form {
			Section(header: Text("Organic Elements").accessibilityHidden(true)) {
				VStack(alignment: .leading) {
					Text("Rain Volume").accessibilityHidden(true)
					Slider(value: $engine.rainVolume, in: 0...1)
						.accessibilityLabel("Rain Volume")
				}
				VStack(alignment: .leading) {
					Text("Organic Heartbeat Volume").accessibilityHidden(true)
					Slider(value: $engine.organicHeartbeatVolume, in: 0...1)
						.accessibilityLabel("Organic Heartbeat Volume")
				}
			}
			
			Section(header: Text("External Sources")) {
				HStack {
					Text("Files: \(engine.customFileName)")
					Spacer()
					Button("Browse") { showingFilePicker = true }
				}
				VStack(alignment: .leading) {
					Slider(value: $engine.customFileVolume, in: 0...1)
						.accessibilityLabel("Custom File Volume")
				}
			}
		}
		.fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio]) { result in
			switch result {
			case .success(let url): engine.loadCustomFile(url: url)
			case .failure(let error): print(error)
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
					ForEach(0..<engine.profiles.count, id: \.self) {
						Text(engine.profiles[$0].name)
					}
				}
				.pickerStyle(MenuPickerStyle())
			}
			
			Section(header: Text("Heartbeat Anatomy Spatial Placement").accessibilityHidden(true)) {
				Picker("Placement", selection: $engine.placementIndex) {
					ForEach(0..<engine.placementOptions.count, id: \.self) {
						Text(engine.placementOptions[$0])
					}
				}
				.pickerStyle(SegmentedPickerStyle())
				.accessibilityLabel("Heartbeat Anatomy Spatial Placement")
			}
			
			Section(header: Text("Synthesizer Mix").accessibilityHidden(true)) {
				VStack(alignment: .leading) {
					Text("Synth Heartbeat").accessibilityHidden(true)
					Slider(value: $engine.heartbeatVolume, in: 0...1)
						.accessibilityLabel("Synth Heartbeat Volume")
				}
			}
		}
	}
}

struct BreathingView: View {
	@ObservedObject var engine: AudioEngineManager
	var body: some View {
		VStack(spacing: 30) {
			Text(engine.currentBreathingPhase)
				.font(.largeTitle)
				.bold()
				.accessibilityLabel("Current Phase: \(engine.currentBreathingPhase)")
			
			HStack(spacing: 20) {
				Button("4-7-8 Relax") { engine.startBreathingExercise(inhale: 4, hold1: 7, exhale: 8, hold2: 0) }
					.buttonStyle(.borderedProminent)
				
				Button("Box Breathing") { engine.startBreathingExercise(inhale: 4, hold1: 4, exhale: 4, hold2: 4) }
					.buttonStyle(.borderedProminent)
			}
			
			Button("Stop Exercise") { engine.stopBreathingExercise() }
				.foregroundColor(.red)
		}
	}
}

struct SettingsView: View {
	@ObservedObject var engine: AudioEngineManager
	var body: some View {
		Form {
			Section(header: Text("Audio Behavior")) {
				Toggle("Mix with other apps", isOn: $engine.mixWithOthers)
					.accessibilityHint("Allows ASMR Engine to play while watching YouTube or listening to podcasts.")
			}
			Section(header: Text("Voice Preferences")) {
				Toggle("Use Whispered Breathing Cues", isOn: $engine.useWhisper)
			}
		}
	}
}

struct ContentView: View {
	@StateObject var engine = AudioEngineManager()
	
	var body: some View {
		VStack(spacing: 0) {
			TabView {
				SoundscapeView(engine: engine)
					.tabItem { Label("Soundscape", systemImage: "waveform") }
				GeneratorView(engine: engine)
					.tabItem { Label("Generator", systemImage: "bolt.heart") }
				BreathingView(engine: engine)
					.tabItem { Label("Breathing", systemImage: "lungs") }
				SettingsView(engine: engine)
					.tabItem { Label("Settings", systemImage: "gear") }
			}
			
			VStack {
				Slider(value: $engine.masterVolume, in: 0...1)
					.accessibilityLabel("Master Output Volume")
					.padding(.horizontal)
				
				Button(action: { engine.playStop() }) {
					Text(engine.isPlaying ? "Stop All Audio" : "Play Master")
						.frame(maxWidth: .infinity)
						.padding()
						.background(engine.isPlaying ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
						.cornerRadius(10)
				}
				.padding(.horizontal)
			}
			.padding(.bottom)
			.background(Color(UIColor.systemBackground).shadow(radius: 2))
		}
	}
}

@main
struct ASMRHeartbeatApp: App {
	var body: some Scene {
		WindowGroup {
			ContentView()
		}
	}
}