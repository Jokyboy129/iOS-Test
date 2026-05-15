import SwiftUI
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers

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
}

class ImportedTrack: Identifiable, ObservableObject {
	let id: UUID
	@Published var name: String
	@Published var volume: Double {
		didSet { player?.volume = Float(volume * masterVolume) }
	}
	var player: AVAudioPlayer?
	var isAppleMusic: Bool
	var path: String
	var masterVolume: Double = 1.0 {
		didSet { player?.volume = Float(volume * masterVolume) }
	}
	
	init(id: UUID = UUID(), name: String, player: AVAudioPlayer?, volume: Double, isAppleMusic: Bool, path: String) {
		self.id = id
		self.name = name
		self.player = player
		self.volume = volume
		self.isAppleMusic = isAppleMusic
		self.path = path
	}
}

class AudioEngineManager: ObservableObject {
	let engine = AVAudioEngine()
	var sourceNode: AVAudioSourceNode?
	
	var rainPlayer: AVAudioPlayer?
	var organicHeartbeatPlayer: AVAudioPlayer?
	var breathingPlayer: AVAudioPlayer?
	var musicPlayer = MPMusicPlayerController.applicationQueuePlayer
	var silentLoopPlayer: AVAudioPlayer?
	
	@Published var isPlaying = false
	@Published var isBreathing = false
	@Published var importedTracks: [ImportedTrack] = []
	
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
	
	@AppStorage("selectedProfileIndex") var selectedProfileIndex = 0 { didSet { rebuildPrototypes(); updateNowPlaying() } }
	@AppStorage("placementIndex") var placementIndex = 0 { didSet { rebuildPrototypes() } }
	
	@AppStorage("masterVolume") var masterVolume: Double = 1.0 { didSet { updateVolumes() } }
	
	@AppStorage("heartbeatVolume") var heartbeatVolume: Double = 0.0
	@AppStorage("clockVolume") var clockVolume: Double = 0.0
	@AppStorage("brownVolume") var brownVolume: Double = 0.0
	@AppStorage("breathVolume") var breathVolume: Double = 0.0
	
	@AppStorage("rainVolume") var rainVolume: Double = 0.0 { didSet { updateVolumes() } }
	@AppStorage("organicHeartbeatVolume") var organicHeartbeatVolume: Double = 0.0 { didSet { updateVolumes() } }
	
	@AppStorage("panHeartIndex") var panHeartIndex = 0
	@AppStorage("panClockIndex") var panClockIndex = 0
	@AppStorage("panBrownIndex") var panBrownIndex = 0
	@AppStorage("panBreathIndex") var panBreathIndex = 0
	
	@AppStorage("clockTypeIndex") var clockTypeIndex = 0 { didSet { rebuildPrototypes() } }
	@AppStorage("syncClock") var syncClock = false { didSet { rebuildPrototypes() } }
	
	@AppStorage("mixWithOthers") var mixWithOthers = false { didSet { applyAudioSessionSettings() } }
	@AppStorage("useWhisper") var useWhisper = false
	
	@AppStorage("savedTracksJSON") var savedTracksJSON: Data = Data()
	
	// Alarm Properties
	@AppStorage("alarmTimeRef") var alarmTimeRef: Double = Date().timeIntervalSince1970
	@Published var alarmTime: Date = Date() { didSet { alarmTimeRef = alarmTime.timeIntervalSince1970 } }
	@AppStorage("isAlarmOn") var isAlarmOn: Bool = false { didSet { toggleSilentBackgroundLoop() } }
	
	@AppStorage("alarmTrackPath") var alarmTrackPath: String = ""
	@AppStorage("alarmTrackIsAppleMusic") var alarmTrackIsAppleMusic: Bool = false
	@AppStorage("alarmTrackNameStorage") var alarmTrackNameStorage: String = "None"
	
	var alarmPlayer: AVAudioPlayer?
	var alarmTimer: Timer?
	var fadeTimer: Timer?
	
	// Generator Buffers
	private var lubL = [Float]()
	private var lubR = [Float]()
	private var dubL = [Float]()
	private var dubR = [Float]()
	private var lubEnv = [Float]()
	private var dubEnv = [Float]()
	private var brownL = [Float]()
	private var brownR = [Float]()
	private var breathL = [Float]()
	private var breathR = [Float]()
	private var whooshL = [Float]()
	private var whooshR = [Float]()
	private var clk = [Float]()
	
	private var nBeat = 0
	private var nNoise = 0
	private var nClock = 0
	
	private var frameIdx = 0
	private let sampleRate: Double = 44100.0
	
	private var breathingTask: Task<Void, Never>?
	private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
	@Published var currentBreathingPhase: String = "Ready"
	
	init() {
		alarmTime = Date(timeIntervalSince1970: alarmTimeRef)
		generateSilentWavIfNeeded()
		applyAudioSessionSettings()
		setupOrganicPlayers()
		loadTracks()
		loadAlarmTrack()
		setupMediaControls()
		setupObservers()
		rebuildPrototypes()
		updateVolumes()
		startAlarmMonitor()
		toggleSilentBackgroundLoop()
	}
	
	private func applyAudioSessionSettings() {
		do {
			let session = AVAudioSession.sharedInstance()
			let options: AVAudioSession.CategoryOptions = mixWithOthers ? [.mixWithOthers] : []
			try session.setCategory(.playback, mode: .default, options: options)
			try session.setPreferredSampleRate(sampleRate)
			try session.setActive(true, options: .notifyOthersOnDeactivation)
		} catch {
			print("Audio Session error: \(error)")
		}
	}
	
	private func updateVolumes() {
		engine.mainMixerNode.outputVolume = Float(masterVolume)
		rainPlayer?.volume = Float(rainVolume * masterVolume)
		organicHeartbeatPlayer?.volume = Float(organicHeartbeatVolume * masterVolume)
		for track in importedTracks {
			track.masterVolume = masterVolume
		}
	}
	
	private func generateSilentWavIfNeeded() {
		let fm = FileManager.default
		let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let fileURL = docs.appendingPathComponent("silence.wav")
		
		guard !fm.fileExists(atPath: fileURL.path) else { return }
		
		let sampleRate: Int32 = 44100
		let numChannels: Int16 = 2
		let bitsPerSample: Int16 = 16
		let durationInSeconds: Int = 2
		
		let numSamples = sampleRate * Int32(durationInSeconds)
		let subChunk2Size = numSamples * Int32(numChannels) * Int32(bitsPerSample / 8)
		let chunkSize = 36 + subChunk2Size
		
		var header = Data()
		
		header.append(contentsOf: [UInt8]("RIFF".utf8))
		header.append(Data(bytes: [chunkSize], count: 4))
		header.append(contentsOf: [UInt8]("WAVE".utf8))
		
		header.append(contentsOf: [UInt8]("fmt ".utf8))
		header.append(Data(bytes: [Int32(16)], count: 4))
		header.append(Data(bytes: [Int16(1)], count: 2))
		header.append(Data(bytes: [numChannels], count: 2))
		header.append(Data(bytes: [sampleRate], count: 4))
		
		let byteRate = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
		header.append(Data(bytes: [byteRate], count: 4))
		
		let blockAlign = numChannels * (bitsPerSample / 8)
		header.append(Data(bytes: [blockAlign], count: 2))
		header.append(Data(bytes: [bitsPerSample], count: 2))
		
		header.append(contentsOf: [UInt8]("data".utf8))
		header.append(Data(bytes: [subChunk2Size], count: 4))
		
		let silenceData = Data(repeating: 0, count: Int(subChunk2Size))
		header.append(silenceData)
		
		try? header.write(to: fileURL)
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
		guard let url = Bundle.main.url(forResource: filename, withExtension: "wav") else {
			print("Missing built-in file: \(filename).wav")
			return nil
		}
		do {
			let player = try AVAudioPlayer(contentsOf: url)
			player.numberOfLoops = -1
			player.prepareToPlay()
			return player
		} catch {
			print("Could not load \(filename): \(error)")
			return nil
		}
	}
	
	private func setupOrganicPlayers() {
		rainPlayer = loadPlayer(filename: "RAIN")
		organicHeartbeatPlayer = loadPlayer(filename: "HEARTBEAT")
	}
	
	func addFile(url: URL, isAlarm: Bool = false) {
		guard url.startAccessingSecurityScopedResource() else { return }
		defer { url.stopAccessingSecurityScopedResource() }
		
		let fm = FileManager.default
		let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let filename = UUID().uuidString + "-" + url.lastPathComponent
		let dest = docs.appendingPathComponent(filename)
		
		do {
			try fm.copyItem(at: url, to: dest)
			let player = try AVAudioPlayer(contentsOf: dest)
			player.numberOfLoops = -1
			player.prepareToPlay()
			
			if isAlarm {
				alarmPlayer = player
				alarmTrackPath = filename
				alarmTrackIsAppleMusic = false
				alarmTrackNameStorage = url.lastPathComponent
			} else {
				let track = ImportedTrack(name: url.lastPathComponent, player: player, volume: 0.5, isAppleMusic: false, path: filename)
				track.masterVolume = masterVolume
				if isPlaying { player.play() }
				importedTracks.append(track)
				saveTracks()
			}
		} catch {
			print("File loading error: \(error)")
		}
	}
	
	func addAppleMusic(items: [MPMediaItem], isAlarm: Bool = false) {
		for item in items {
			guard let url = item.assetURL else { continue }
			do {
				let player = try AVAudioPlayer(contentsOf: url)
				player.numberOfLoops = -1
				player.prepareToPlay()
				
				if isAlarm {
					alarmPlayer = player
					alarmTrackPath = String(item.persistentID)
					alarmTrackIsAppleMusic = true
					alarmTrackNameStorage = item.title ?? "Unknown Track"
					break
				} else {
					let track = ImportedTrack(
						name: item.title ?? "Unknown Track",
						player: player,
						volume: 0.5,
						isAppleMusic: true,
						path: String(item.persistentID)
					)
					track.masterVolume = masterVolume
					if isPlaying { player.play() }
					importedTracks.append(track)
					saveTracks()
				}
			} catch {
				print("Failed to load Apple Music track: \(error)")
			}
		}
	}
	
	func removeTracks(at offsets: IndexSet) {
		for index in offsets {
			let track = importedTracks[index]
			track.player?.stop()
			if !track.isAppleMusic {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let fileURL = docs.appendingPathComponent(track.path)
				try? FileManager.default.removeItem(at: fileURL)
			}
		}
		importedTracks.remove(atOffsets: offsets)
		saveTracks()
	}
	
	func saveTracks() {
		let dataList = importedTracks.map { TrackData(id: $0.id, name: $0.name, path: $0.path, volume: $0.volume, isAppleMusic: $0.isAppleMusic) }
		if let encoded = try? JSONEncoder().encode(dataList) {
			savedTracksJSON = encoded
		}
	}
	
	private func loadTracks() {
		guard let dataList = try? JSONDecoder().decode([TrackData].self, from: savedTracksJSON) else { return }
		for data in dataList {
			var player: AVAudioPlayer?
			if data.isAppleMusic {
				if let pid = UInt64(data.path) {
					let query = MPMediaQuery.songs()
					let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
					query.addFilterPredicate(predicate)
					if let item = query.items?.first, let url = item.assetURL {
						player = try? AVAudioPlayer(contentsOf: url)
					}
				}
			} else {
				let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
				let url = docs.appendingPathComponent(data.path)
				player = try? AVAudioPlayer(contentsOf: url)
			}
			
			player?.numberOfLoops = -1
			player?.prepareToPlay()
			
			let track = ImportedTrack(id: data.id, name: data.name, player: player, volume: data.volume, isAppleMusic: data.isAppleMusic, path: data.path)
			track.masterVolume = masterVolume
			importedTracks.append(track)
		}
	}
	
	private func loadAlarmTrack() {
		guard !alarmTrackPath.isEmpty else { return }
		if alarmTrackIsAppleMusic {
			if let pid = UInt64(alarmTrackPath) {
				let query = MPMediaQuery.songs()
				let predicate = MPMediaPropertyPredicate(value: pid, forProperty: MPMediaItemPropertyPersistentID)
				query.addFilterPredicate(predicate)
				if let item = query.items?.first, let url = item.assetURL {
					alarmPlayer = try? AVAudioPlayer(contentsOf: url)
				}
			}
		} else {
			let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			let url = docs.appendingPathComponent(alarmTrackPath)
			alarmPlayer = try? AVAudioPlayer(contentsOf: url)
		}
		alarmPlayer?.numberOfLoops = -1
		alarmPlayer?.prepareToPlay()
	}
	
	private func startAlarmMonitor() {
		alarmTimer?.invalidate()
		alarmTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			self?.checkAlarm()
		}
	}
	
	private func checkAlarm() {
		guard isAlarmOn else { return }
		let now = Date()
		let cal = Calendar.current
		if cal.component(.hour, from: now) == cal.component(.hour, from: alarmTime) &&
		   cal.component(.minute, from: now) == cal.component(.minute, from: alarmTime) {
			triggerAlarm()
		}
	}
	
	private func triggerAlarm() {
		isAlarmOn = false
		do {
			try AVAudioSession.sharedInstance().setActive(true)
		} catch {}
		
		alarmPlayer?.volume = 0
		alarmPlayer?.play()
		
		let initialMaster = masterVolume
		var fadeStep = 0
		let totalSteps = 300
		
		fadeTimer?.invalidate()
		fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
			guard let self = self else { return }
			fadeStep += 1
			let progress = Double(fadeStep) / Double(totalSteps)
			
			self.alarmPlayer?.volume = Float(progress * 1.0)
			
			if self.isPlaying {
				self.masterVolume = initialMaster * (1.0 - progress)
			}
			
			if fadeStep >= totalSteps {
				timer.invalidate()
				if self.isPlaying {
					self.playStop()
					self.masterVolume = initialMaster
				}
			}
		}
	}
	
	func playBreathingCue(type: String) {
		let suffix = useWhisper ? "_WHISPER" : ""
		let filename = "\(type)\(suffix)"
		
		guard let url = Bundle.main.url(forResource: filename, withExtension: "wav") else {
			print("Missing breathing cue: \(filename).wav")
			return
		}
		do {
			breathingPlayer = try AVAudioPlayer(contentsOf: url)
			breathingPlayer?.volume = Float(masterVolume)
			breathingPlayer?.play()
		} catch {
			print("Error playing breathing cue: \(error)")
		}
	}
	
	func startBreathingExercise(inhale: Int, hold1: Int, exhale: Int, hold2: Int) {
		breathingTask?.cancel()
		isBreathing = true
		
		// Request background assertion so Task sleep doesn't get culled upon locking the screen
		backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BreathingExercise") { [weak self] in
			self?.stopBreathingExercise()
		}
		
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
			if backgroundTaskID != .invalid {
				UIApplication.shared.endBackgroundTask(backgroundTaskID)
				backgroundTaskID = .invalid
			}
		}
	}
	
	func stopBreathingExercise() {
		breathingTask?.cancel()
		isBreathing = false
		currentBreathingPhase = "Ready"
		if backgroundTaskID != .invalid {
			UIApplication.shared.endBackgroundTask(backgroundTaskID)
			backgroundTaskID = .invalid
		}
	}
	
	private func setupAudio() {
		let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
		
		sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
			guard let self = self else { return noErr }
			let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
			
			if self.nBeat == 0 || self.nNoise == 0 || self.nClock == 0 {
				return noErr
			}
			
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
				let flowEnv = 0.6 + 0.4 * (self.lubEnv[idxBeat] + self.dubEnv[idxBeat])
				
				let config = self.profiles[self.selectedProfileIndex]
				let wVol = Float(config.whooshVol)
				let whooshL = self.whooshL[idxNoise] * flowEnv * wVol
				let whooshR = self.whooshR[idxNoise] * flowEnv * wVol
				
				let posH = self.getPanPos(mode: self.panHeartIndex, time: tChunk)
				let (chunkHL, chunkHR) = self.applyStereoPan(inL: beatL + whooshL, inR: beatR + whooshR, pos: posH, vol: vHeart)
				
				var chunkCL: Float = 0
				var chunkCR: Float = 0
				if vClock > 0 {
					let clkWave = self.clk[idxClock]
					let posC = self.getPanPos(mode: self.panClockIndex, time: tChunk)
					let pannedC = self.applyStereoPan(inL: clkWave, inR: clkWave, pos: posC, vol: vClock * 0.4)
					chunkCL = pannedC.0
					chunkCR = pannedC.1
				}
				
				var chunkBL: Float = 0
				var chunkBR: Float = 0
				if vBrown > 0 {
					let posB = self.getPanPos(mode: self.panBrownIndex, time: tChunk)
					let pannedB = self.applyStereoPan(inL: self.brownL[idxNoise], inR: self.brownR[idxNoise], pos: posB, vol: vBrown * 0.5)
					chunkBL = pannedB.0
					chunkBR = pannedB.1
				}
				
				var chunkBrL: Float = 0
				var chunkBrR: Float = 0
				if vBreath > 0 {
					let breathPhase = fmod(tChunk / 6.0, 1.0)
					let inhale: Float = (breathPhase < 0.45) ? sin(Float.pi * (breathPhase / 0.45)) : 0.0
					let exhale: Float = (breathPhase >= 0.5 && breathPhase < 0.95) ? sin(Float.pi * ((breathPhase - 0.5) / 0.45)) : 0.0
					let breathEnv = max(0, inhale * 0.8 + exhale * 0.6)
					
					let posBr = self.getPanPos(mode: self.panBreathIndex, time: tChunk)
					let pannedBr = self.applyStereoPan(inL: self.breathL[idxNoise] * breathEnv, inR: self.breathR[idxNoise] * breathEnv, pos: posBr, vol: vBreath * 0.6)
					chunkBrL = pannedBr.0
					chunkBrR = pannedBr.1
				}
				
				let finalL = (chunkHL + chunkCL + chunkBL + chunkBrL) / totalGain
				let finalR = (chunkHR + chunkCR + chunkBR + chunkBrR) / totalGain
				
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
		repeat {
			u1 = Float.random(in: 0..<1)
		} while u1 == 0
		let u2 = Float.random(in: 0..<1)
		return sqrt(-2.0 * log(u1)) * cos(2.0 * Float.pi * u2)
	}
	
	private func generateSeamlessNoise(length: Int, lpfFreq: Double? = nil, isBrown: Bool = false) -> [Float] {
		let crossfadeLength = Int(sampleRate * 1.0)
		let totalLength = length + crossfadeLength
		var noise = [Float](repeating: 0, count: totalLength)
		var maxVal: Float = 0
		var lastBrown: Float = 0
		
		var filter1: Float = 0
		var filter2: Float = 0
		var filter3: Float = 0
		var filter4: Float = 0
		
		let alpha: Float
		if let freq = lpfFreq {
			let dt = 1.0 / sampleRate
			let rc = 1.0 / (2.0 * Double.pi * (freq * 0.5))
			alpha = Float(dt / (rc + dt))
		} else {
			alpha = 1.0
		}
		
		for i in 0..<totalLength {
			let white = gaussianRandom()
			lastBrown = 0.995 * lastBrown + 0.025 * white
			
			if isBrown {
				noise[i] = lastBrown
			} else {
				filter1 = filter1 + alpha * (lastBrown - filter1)
				filter2 = filter2 + alpha * (filter1 - filter2)
				filter3 = filter3 + alpha * (filter2 - filter3)
				filter4 = filter4 + alpha * (filter3 - filter4)
				noise[i] = filter4
			}
		}
		
		for i in 0..<crossfadeLength {
			let ratio = Float(i) / Float(crossfadeLength)
			noise[i] = noise[length + i] * (1.0 - ratio) + noise[i] * ratio
		}
		
		var finalNoise = Array(noise[0..<length])
		
		for i in 0..<length {
			if abs(finalNoise[i]) > maxVal { maxVal = abs(finalNoise[i]) }
		}
		
		if maxVal > 0 {
			for i in 0..<length { finalNoise[i] /= maxVal }
		}
		
		return finalNoise
	}
	
	private func rebuildPrototypes() {
		let config = profiles[selectedProfileIndex]
		
		let bpm = config.bpm
		nBeat = Int((60.0 / bpm) * sampleRate)
		let actualBeatDur = Double(nBeat) / sampleRate
		
		let atkSamples = Int(0.04 * sampleRate)
		let relSamples = Int(0.02 * sampleRate)
		
		let trueSubFreq = max(1, round(config.subFreq * actualBeatDur)) / actualBeatDur
		let idxStart = Int(config.dubDelay * sampleRate)
		
		let placement = placementOptions[placementIndex]
		
		var localLubL = [Float](repeating: 0, count: nBeat)
		var localLubR = [Float](repeating: 0, count: nBeat)
		var localDubL = [Float](repeating: 0, count: nBeat)
		var localDubR = [Float](repeating: 0, count: nBeat)
		var localLubEnv = [Float](repeating: 0, count: nBeat)
		var localDubEnv = [Float](repeating: 0, count: nBeat)
		
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
			
			var dEnv: Double = 0
			var subDub: Double = 0
			var dub: Double = 0
			
			if i >= idxStart {
				let tAct = t - config.dubDelay
				dEnv = exp(-config.dubDecay * tAct)
				let relI = i - idxStart
				if relI < atkSamples { dEnv *= pow(sin((Double.pi / 2.0) * Double(relI) / Double(atkSamples)), 2) }
				if i > nBeat - relSamples { dEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
				
				var sDEnv = exp(-config.subDecay * tAct)
				if relI < atkSamples { sDEnv *= pow(sin((Double.pi / 2.0) * Double(relI) / Double(atkSamples)), 2) }
				if i > nBeat - relSamples { sDEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
				subDub = sin(2 * Double.pi * trueSubFreq * t) * sDEnv * config.subVol * 0.85
				
				let dubPhase = 2 * Double.pi * (config.dubBase * tAct - (config.dubDrop / config.dubDecay) * exp(-config.dubDecay * tAct))
				let dub = sin(dubPhase) * dEnv
			}
			localDubEnv[i] = Float(dEnv)
			
			let combinedLub = Float((lub + subLub))
			let combinedDub = Float((dub + subDub))
			
			if placement == "Center Beats & Flow" {
				localLubL[i] = combinedLub * 0.85
				localLubR[i] = combinedLub * 0.85
				localDubL[i] = combinedDub * 0.85
				localDubR[i] = combinedDub * 0.85
			} else if placement == "Lub Left Ear / Dub Right Ear" {
				localLubL[i] = combinedLub; localLubR[i] = 0; localDubL[i] = 0; localDubR[i] = combinedDub
			} else {
				localLubL[i] = 0; localLubR[i] = combinedLub; localDubL[i] = combinedDub; localDubR[i] = 0
			}
		}
		
		var globalPeak: Float = 0
		for i in 0..<nBeat {
			let peakL = abs(localLubL[i] + localDubL[i])
			let peakR = abs(localLubR[i] + localDubR[i])
			if peakL > globalPeak { globalPeak = peakL }
			if peakR > globalPeak { globalPeak = peakR }
		}
		if globalPeak > 0 {
			for i in 0..<nBeat {
				localLubL[i] = (localLubL[i] / globalPeak) * 0.70
				localLubR[i] = (localLubR[i] / globalPeak) * 0.70
				localDubL[i] = (localDubL[i] / globalPeak) * 0.70
				localDubR[i] = (localDubR[i] / globalPeak) * 0.70
			}
		}
		
		self.lubL = localLubL
		self.lubR = localLubR
		self.dubL = localDubL
		self.dubR = localDubR
		self.lubEnv = localLubEnv
		self.dubEnv = localDubEnv
		
		nNoise = Int(sampleRate * 5)
		if brownL.isEmpty {
			brownL = generateSeamlessNoise(length: nNoise, isBrown: true)
			brownR = generateSeamlessNoise(length: nNoise, isBrown: true)
			breathL = generateSeamlessNoise(length: nNoise, lpfFreq: 600)
			breathR = generateSeamlessNoise(length: nNoise, lpfFreq: 600)
		}
		whooshL = generateSeamlessNoise(length: nNoise, lpfFreq: config.noiseLpf)
		whooshR = generateSeamlessNoise(length: nNoise, lpfFreq: config.noiseLpf)
		
		let clkType = clockOptions[clockTypeIndex]
		var nClockProto = 0
		var ticksPerBeat = 1
		
		if clkType == "Pocket Watch" { nClockProto = Int(sampleRate / 2); ticksPerBeat = 2 }
		else if clkType == "Quartz Wall Clock" { nClockProto = Int(sampleRate); ticksPerBeat = 1 }
		else if clkType == "Grandfather Clock" { nClockProto = Int(sampleRate * 1.5); ticksPerBeat = 1 }
		else { nClockProto = Int(sampleRate / 1.5); ticksPerBeat = 1 }
		
		var clkProto = [Float](repeating: 0, count: nClockProto)
		for i in 0..<nClockProto {
			let tc = Double(i) / sampleRate
			let randomGaussian = gaussianRandom() * 0.3
			if clkType == "Quartz Wall Clock" {
				let body = (sin(2 * Double.pi * 1200 * tc) * 0.15 + sin(2 * Double.pi * 2000 * tc) * 0.05) * exp(-120 * tc)
				clkProto[i] = Float(body) + randomGaussian * Float(exp(-300 * tc))
			} else if clkType == "Pocket Watch" {
				let body = (sin(2 * Double.pi * 4000 * tc) * 0.1 + sin(2 * Double.pi * 6000 * tc) * 0.05) * exp(-200 * tc)
				clkProto[i] = Float(body) + randomGaussian * Float(exp(-800 * tc)) * 1.5
			} else if clkType == "Grandfather Clock" {
				let body = (sin(2 * Double.pi * 350 * tc) * 0.2 + sin(2 * Double.pi * 800 * tc) * 0.1) * exp(-60 * tc)
				clkProto[i] = Float(body) + randomGaussian * Float(exp(-500 * tc)) * 1.2
			} else {
				let body = (sin(2 * Double.pi * 1000 * tc) * 0.3 + sin(2 * Double.pi * 2000 * tc) * 0.1) * exp(-100 * tc)
				clkProto[i] = Float(body) + randomGaussian * Float(exp(-600 * tc)) * 1.2
			}
		}
		
		if syncClock {
			clk = [Float](repeating: 0, count: nBeat)
			let tickInterval = nBeat / ticksPerBeat
			for i in 0..<ticksPerBeat {
				let startIdx = i * tickInterval
				let copyLen = min(nClockProto, nBeat - startIdx)
				for j in 0..<copyLen {
					clk[startIdx + j] += clkProto[j]
				}
			}
			nClock = nBeat
		} else {
			clk = clkProto
			nClock = nClockProto
		}
	}
	
	func playStop() {
		if isPlaying {
			engine.pause()
			rainPlayer?.pause()
			organicHeartbeatPlayer?.pause()
			for track in importedTracks { track.player?.pause() }
			musicPlayer.pause()
			isPlaying = false
			UIAccessibility.post(notification: .announcement, argument: "Engine halted.")
		} else {
			do {
				// Re-verify and strictly configure the context session state BEFORE touching the active node pipelines.
				let session = AVAudioSession.sharedInstance()
				let options: AVAudioSession.CategoryOptions = mixWithOthers ? [.mixWithOthers] : []
				try session.setCategory(.playback, mode: .default, options: options)
				try session.setActive(true)
				
				if sourceNode == nil { setupAudio() }
				
				engine.prepare()
				try engine.start()
				
				// Added dispatch security buffer to let core AudioGraph finish hardware alignment before pushing data streams
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
					guard let self = self else { return }
					// Verify engine didn't immediately stall during line negotiation
					guard self.engine.isRunning else {
						print("Engine stalled safely before channel explosion protection triggered.")
						return
					}
					self.rainPlayer?.play()
					self.organicHeartbeatPlayer?.play()
					for track in self.importedTracks { track.player?.play() }
					self.musicPlayer.play()
					self.isPlaying = true
					self.updateNowPlaying()
					UIAccessibility.post(notification: .announcement, argument: "Audio stream active.")
				}
			} catch { 
				print("Engine start error: \(error)") 
			}
		}
	}
	
	private func setupMediaControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		
		commandCenter.playCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if !self.isPlaying {
				self.playStop()
				return .success
			}
			return .commandFailed
		}
		
		commandCenter.pauseCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			if self.isPlaying {
				self.playStop()
				return .success
			}
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
			} else if type == .ended {
				guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
				let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
				if options.contains(.shouldResume) {
					if !self.isPlaying { self.playStop() }
				}
			}
		}
		
		NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
			guard let self = self, let userInfo = notification.userInfo,
				  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
				  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
			
			if reason == .oldDeviceUnavailable {
				if self.isPlaying { self.playStop() }
			}
		}
		
		NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
			guard let self = self else { return }
			if self.isPlaying {
				do {
					try self.engine.start()
					self.rainPlayer?.play()
					self.organicHeartbeatPlayer?.play()
					for track in self.importedTracks { track.player?.play() }
				} catch {
					print("Failed to restart engine after config change: \(error)")
				}
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

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	class Coordinator: NSObject, MPMediaPickerControllerDelegate {
		let parent: MediaPicker
		
		init(_ parent: MediaPicker) {
			self.parent = parent
		}
		
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
			Text(track.name)
				.font(.headline)
			Slider(value: $track.volume, in: 0...1)
				.accessibilityLabel("\(track.name) Volume")
				.onChange(of: track.volume) { _ in
					engine.saveTracks()
				}
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
						Slider(value: $engine.rainVolume, in: 0...1)
							.accessibilityLabel("Rain Volume")
					}
					VStack(alignment: .leading) {
						Text("Organic Heartbeat Volume").accessibilityHidden(true)
						Slider(value: $engine.organicHeartbeatVolume, in: 0...1)
							.accessibilityLabel("Organic Heartbeat Volume")
					}
				}
				
				Section(header: Text("Imported Audio")) {
					if engine.importedTracks.isEmpty {
						Text("No files imported.")
							.foregroundColor(.secondary)
					} else {
						ForEach(engine.importedTracks) { track in
							TrackRowView(track: track, engine: engine)
						}
						.onDelete { offsets in
							engine.removeTracks(at: offsets)
						}
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
				case .success(let urls):
					for url in urls { engine.addFile(url: url) }
				case .failure(let error):
					print(error)
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
			
			Section(header: Text("Procedural Layer Mixer").accessibilityHidden(true)) {
				VStack(alignment: .leading) {
					Text("Synth Heartbeat").accessibilityHidden(true)
					Slider(value: $engine.heartbeatVolume, in: 0...1)
						.accessibilityLabel("Synth Heartbeat Volume")
					Picker("Heartbeat Pan", selection: $engine.panHeartIndex) {
						ForEach(0..<engine.panOptions.count, id: \.self) { Text(engine.panOptions[$0]) }
					}
				}
				.padding(.vertical, 4)
				
				VStack(alignment: .leading) {
					Text("Clock Ticking").accessibilityHidden(true)
					Slider(value: $engine.clockVolume, in: 0...1)
						.accessibilityLabel("Clock Volume")
					Picker("Clock Type", selection: $engine.clockTypeIndex) {
						ForEach(0..<engine.clockOptions.count, id: \.self) { Text(engine.clockOptions[$0]) }
					}
					Toggle("Sync to Heartbeat", isOn: $engine.syncClock)
				}
				.padding(.vertical, 4)
				
				VStack(alignment: .leading) {
					Text("Brown Noise").accessibilityHidden(true)
					Slider(value: $engine.brownVolume, in: 0...1)
						.accessibilityLabel("Brown Noise Volume")
				}
				.padding(.vertical, 4)
				
				VStack(alignment: .leading) {
					Text("Slow Breathing Base").accessibilityHidden(true)
					Slider(value: $engine.breathVolume, in: 0...1)
						.accessibilityLabel("Slow Breathing Volume")
				}
				.padding(.vertical, 4)
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
					.disabled(engine.isBreathing)
				
				Button("Box Breathing") { engine.startBreathingExercise(inhale: 4, hold1: 4, exhale: 4, hold2: 4) }
					.buttonStyle(.borderedProminent)
					.disabled(engine.isBreathing)
			}
			
			if engine.isBreathing {
				Button("Stop Exercise") { engine.stopBreathingExercise() }
					.foregroundColor(.red)
					.padding(.top, 20)
			}
		}
	}
}

struct AlarmView: View {
	@ObservedObject var engine: AudioEngineManager
	@State private var showingFilePicker = false
	@State private var showingMusicPicker = false
	
	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("Alarm Time")) {
					DatePicker("Time", selection: $engine.alarmTime, displayedComponents: .hourAndMinute)
						.datePickerStyle(WheelDatePickerStyle())
						.accessibilityLabel("Set Alarm Time")
				}
				
				Section(header: Text("Alarm Track")) {
					HStack {
						Text(engine.alarmTrackNameStorage)
						Spacer()
						Menu("Select Sound") {
							Button("From Files") { showingFilePicker = true }
							Button("From Apple Music") { showingMusicPicker = true }
						}
					}
				}
				
				Section {
					Toggle("Alarm Enabled", isOn: $engine.isAlarmOn)
				}
			}
			.navigationTitle("Alarm")
			.navigationBarTitleDisplayMode(.inline)
			.fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
				switch result {
				case .success(let urls):
					if let url = urls.first { engine.addFile(url: url, isAlarm: true) }
				case .failure(let error):
					print(error)
				}
			}
			.sheet(isPresented: $showingMusicPicker) {
				MediaPicker(isPresented: $showingMusicPicker) { items in
					engine.addAppleMusic(items: items.items, isAlarm: true)
				}
			}
		}
	}
}

struct SettingsView: View {
	@ObservedObject var engine: AudioEngineManager
	var body: some View {
		Form {
			Section(header: Text("Audio Behavior")) {
				Toggle("Mix with other apps", isOn: $engine.mixWithOthers)
					.accessibilityHint("Allows Sleep Engine to play while watching YouTube or listening to podcasts.")
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
			VStack {
				Slider(value: $engine.masterVolume, in: 0...1)
					.accessibilityLabel("Master Output Volume")
					.padding(.horizontal)
					.padding(.top, 10)
				
				Button(action: { engine.playStop() }) {
					Text(engine.isPlaying ? "Stop All Audio" : "Play Master")
						.frame(maxWidth: .infinity)
						.padding()
						.background(engine.isPlaying ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
						.cornerRadius(10)
				}
				.padding(.horizontal)
				.padding(.bottom, 10)
			}
			.background(Color(UIColor.secondarySystemBackground).shadow(radius: 1))
			
			TabView {
				SoundscapeView(engine: engine)
					.tabItem { Label("Soundscape", systemImage: "waveform") }
				GeneratorView(engine: engine)
					.tabItem { Label("Generator", systemImage: "bolt.heart") }
				BreathingView(engine: engine)
					.tabItem { Label("Breathing", systemImage: "lungs") }
				AlarmView(engine: engine)
					.tabItem { Label("Alarm", systemImage: "alarm") }
				SettingsView(engine: engine)
					.tabItem { Label("Settings", systemImage: "gear") }
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