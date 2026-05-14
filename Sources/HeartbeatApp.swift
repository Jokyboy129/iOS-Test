import SwiftUI
import AVFoundation

struct HeartbeatProfile: Hashable {
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
	
	@Published var isPlaying = false
	
	let profiles: [HeartbeatProfile] = [
		HeartbeatProfile(name: "ASMR Blood Flow (60 BPM)", bpm: 60, lubBase: 40, lubDrop: 15, lubDecay: 18, dubBase: 50, dubDrop: 20, dubDecay: 22, dubDelay: 0.30, subFreq: 35, subVol: 0.25, subDecay: 6, whooshVol: 0.50, noiseLpf: 450),
		HeartbeatProfile(name: "Standard Resting Heart (72 BPM)", bpm: 72, lubBase: 45, lubDrop: 10, lubDecay: 20, dubBase: 55, dubDrop: 15, dubDecay: 25, dubDelay: 0.28, subFreq: 30, subVol: 0.30, subDecay: 5, whooshVol: 0.30, noiseLpf: 500),
		HeartbeatProfile(name: "Womb Simulation (55 BPM)", bpm: 55, lubBase: 55, lubDrop: 20, lubDecay: 20, dubBase: 70, dubDrop: 25, dubDecay: 25, dubDelay: 0.35, subFreq: 35, subVol: 0.45, subDecay: 5, whooshVol: 0.60, noiseLpf: 650),
		HeartbeatProfile(name: "Zen Meditation (50 BPM)", bpm: 50, lubBase: 35, lubDrop: 25, lubDecay: 15, dubBase: 45, dubDrop: 30, dubDecay: 18, dubDelay: 0.32, subFreq: 30, subVol: 0.40, subDecay: 4, whooshVol: 0.12, noiseLpf: 150),
		HeartbeatProfile(name: "Deep Sleep Resonance (40 BPM)", bpm: 40, lubBase: 30, lubDrop: 20, lubDecay: 12, dubBase: 35, dubDrop: 25, dubDecay: 15, dubDelay: 0.38, subFreq: 25, subVol: 0.60, subDecay: 4, whooshVol: 0.20, noiseLpf: 200)
	]
	
	let panOptions = ["Center", "Left", "Right", "Soft Left", "Soft Right", "1 Minute Slow Shift", "5 Minute Slow Shift"]
	let clockOptions = ["Quartz Wall Clock", "Pocket Watch", "Grandfather Clock", "Metronome"]
	let placementOptions = ["Center Beats & Flow", "Lub Left Ear / Dub Right Ear", "Lub Right Ear / Dub Left Ear"]
	
	@Published var selectedProfileIndex = 0 { didSet { rebuildPrototypes() } }
	@Published var placementIndex = 0 { didSet { rebuildPrototypes() } }
	
	@Published var masterVolume: Double = 1.0
	@Published var heartbeatVolume: Double = 1.0
	@Published var clockVolume: Double = 0.0
	@Published var brownVolume: Double = 0.0
	@Published var breathVolume: Double = 0.0
	
	@Published var panHeartIndex = 0
	@Published var panClockIndex = 0
	@Published var panBrownIndex = 0
	@Published var panBreathIndex = 0
	
	@Published var clockTypeIndex = 0 { didSet { rebuildPrototypes() } }
	@Published var syncClock = false { didSet { rebuildPrototypes() } }
	
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
	
	init() {
		setupAudio()
		rebuildPrototypes()
	}
	
	private func setupAudio() {
		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, mode: .measurement, options: [])
			try session.setPreferredSampleRate(44100.0)
			try session.setActive(true)
		} catch {
			print("Failed to configure audio session: \(error)")
		}

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
			let vMaster = Float(self.masterVolume)
			
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
				
				let finalL = ((chunkHL + chunkCL + chunkBL + chunkBrL) / totalGain) * vMaster
				let finalR = ((chunkHR + chunkCR + chunkBR + chunkBrR) / totalGain) * vMaster
				
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
	
	func playStop() {
		if isPlaying {
			engine.stop()
			isPlaying = false
			UIAccessibility.post(notification: .announcement, argument: "Engine halted.")
		} else {
			do {
				try engine.start()
				isPlaying = true
				UIAccessibility.post(notification: .announcement, argument: "Audio stream active.")
			} catch {
				print("Engine start error: \(error)")
			}
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
		var noise = [Float](repeating: 0, count: length)
		var maxVal: Float = 0
		var lastOut: Float = 0
		
		var filter1: Float = 0
		var filter2: Float = 0
		var filter3: Float = 0
		var filter4: Float = 0
		
		let alpha: Float
		if let freq = lpfFreq {
			let dt = 1.0 / sampleRate
			let rc = 1.0 / (2.0 * Double.pi * freq)
			alpha = Float(dt / (rc + dt))
		} else {
			alpha = 1.0
		}
		
		for i in 0..<length {
			let white = gaussianRandom()
			
			if isBrown {
				lastOut = (lastOut + (0.02 * white)) / 1.02
				noise[i] = lastOut
			} else {
				filter1 = filter1 + alpha * (white - filter1)
				filter2 = filter2 + alpha * (filter1 - filter2)
				filter3 = filter3 + alpha * (filter2 - filter3)
				filter4 = filter4 + alpha * (filter3 - filter4)
				noise[i] = filter4
			}
			
			if abs(noise[i]) > maxVal { maxVal = abs(noise[i]) }
		}
		
		if maxVal > 0 {
			for i in 0..<length { noise[i] /= maxVal }
		}
		return noise
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
		
		lubL = [Float](repeating: 0, count: nBeat)
		lubR = [Float](repeating: 0, count: nBeat)
		dubL = [Float](repeating: 0, count: nBeat)
		dubR = [Float](repeating: 0, count: nBeat)
		lubEnv = [Float](repeating: 0, count: nBeat)
		dubEnv = [Float](repeating: 0, count: nBeat)
		
		for i in 0..<nBeat {
			let t = Double(i) / sampleRate
			
			var lEnv = exp(-config.lubDecay * t)
			if i < atkSamples { lEnv *= pow(sin((Double.pi / 2.0) * Double(i) / Double(atkSamples)), 2) }
			if i > nBeat - relSamples { lEnv *= pow(cos((Double.pi / 2.0) * Double(i - (nBeat - relSamples)) / Double(relSamples)), 2) }
			lubEnv[i] = Float(lEnv)
			
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
				dub = sin(dubPhase) * dEnv
			}
			dubEnv[i] = Float(dEnv)
			
			let placement = placementOptions[placementIndex]
			let combinedLub = Float((lub + subLub))
			let combinedDub = Float((dub + subDub))
			
			if placement == "Center Beats & Flow" {
				lubL[i] = combinedLub * 0.85
				lubR[i] = combinedLub * 0.85
				dubL[i] = combinedDub * 0.85
				dubR[i] = combinedDub * 0.85
			} else if placement == "Lub Left Ear / Dub Right Ear" {
				lubL[i] = combinedLub; lubR[i] = 0; dubL[i] = 0; dubR[i] = combinedDub
			} else {
				lubL[i] = 0; lubR[i] = combinedLub; dubL[i] = combinedDub; dubR[i] = 0
			}
		}
		
		var globalPeak: Float = 0
		for i in 0..<nBeat {
			let peakL = abs(lubL[i] + dubL[i])
			let peakR = abs(lubR[i] + dubR[i])
			if peakL > globalPeak { globalPeak = peakL }
			if peakR > globalPeak { globalPeak = peakR }
		}
		if globalPeak > 0 {
			for i in 0..<nBeat {
				lubL[i] = (lubL[i] / globalPeak) * 0.70
				lubR[i] = (lubR[i] / globalPeak) * 0.70
				dubL[i] = (dubL[i] / globalPeak) * 0.70
				dubR[i] = (dubR[i] / globalPeak) * 0.70
			}
		}
		
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
}

struct ContentView: View {
	@StateObject var engine = AudioEngineManager()
	
	var body: some View {
		NavigationView {
			Form {
				Section(header: Text("1. Select Base Speed & Tone Profile").accessibilityHidden(true)) {
					Picker("Tone Profile", selection: $engine.selectedProfileIndex) {
						ForEach(0..<engine.profiles.count, id: \.self) {
							Text(engine.profiles[$0].name)
						}
					}
					.pickerStyle(MenuPickerStyle())
					.accessibilityLabel("Select Base Speed and Tone Profile")
					.accessibilityHint("Choose the foundational heartbeat rhythm and equalization.")
				}
				
				Section(header: Text("2. Heartbeat Anatomy (Static Placement)").accessibilityHidden(true)) {
					Picker("Spatial Placement", selection: $engine.placementIndex) {
						ForEach(0..<engine.placementOptions.count, id: \.self) {
							Text(engine.placementOptions[$0])
						}
					}
					.pickerStyle(MenuPickerStyle())
					.accessibilityLabel("Heartbeat Anatomy Spatial Placement")
				}
				
				Section(header: Text("3. Atmosphere & 3D Layer Mixer").accessibilityHidden(true)) {
					VStack(alignment: .leading) {
						Text("Heartbeat Volume").accessibilityHidden(true)
						Slider(value: $engine.heartbeatVolume, in: 0...1)
							.accessibilityLabel("Heartbeat Volume")
							.accessibilityValue("\(Int(engine.heartbeatVolume * 100)) percent")
						
						Picker("Heartbeat Pan", selection: $engine.panHeartIndex) {
							ForEach(0..<engine.panOptions.count, id: \.self) { Text(engine.panOptions[$0]) }
						}
						.accessibilityLabel("Heartbeat 3D Panning")
					}
					.padding(.vertical, 4)
					
					VStack(alignment: .leading) {
						Text("Clock Ticking Volume").accessibilityHidden(true)
						Slider(value: $engine.clockVolume, in: 0...1)
							.accessibilityLabel("Clock Ticking Volume")
							.accessibilityValue("\(Int(engine.clockVolume * 100)) percent")
						
						Picker("Clock Pan", selection: $engine.panClockIndex) {
							ForEach(0..<engine.panOptions.count, id: \.self) { Text(engine.panOptions[$0]) }
						}
						.accessibilityLabel("Clock 3D Panning")
						
						Picker("Clock Type", selection: $engine.clockTypeIndex) {
							ForEach(0..<engine.clockOptions.count, id: \.self) { Text(engine.clockOptions[$0]) }
						}
						.accessibilityLabel("Clock Type Selection")
						
						Toggle("Sync to Heartbeat", isOn: $engine.syncClock)
							.accessibilityLabel("Synchronize Clock Speed to Heartbeat")
					}
					.padding(.vertical, 4)
					
					VStack(alignment: .leading) {
						Text("Brown Noise Volume").accessibilityHidden(true)
						Slider(value: $engine.brownVolume, in: 0...1)
							.accessibilityLabel("Brown Noise Volume")
							.accessibilityValue("\(Int(engine.brownVolume * 100)) percent")
						
						Picker("Brown Noise Pan", selection: $engine.panBrownIndex) {
							ForEach(0..<engine.panOptions.count, id: \.self) { Text(engine.panOptions[$0]) }
						}
						.accessibilityLabel("Brown Noise 3D Panning")
					}
					.padding(.vertical, 4)
					
					VStack(alignment: .leading) {
						Text("Slow Breathing Volume").accessibilityHidden(true)
						Slider(value: $engine.breathVolume, in: 0...1)
							.accessibilityLabel("Slow Breathing Volume")
							.accessibilityValue("\(Int(engine.breathVolume * 100)) percent")
						
						Picker("Slow Breathing Pan", selection: $engine.panBreathIndex) {
							ForEach(0..<engine.panOptions.count, id: \.self) { Text(engine.panOptions[$0]) }
						}
						.accessibilityLabel("Slow Breathing 3D Panning")
					}
					.padding(.vertical, 4)
				}
				
				Section(header: Text("Master Output Volume").accessibilityHidden(true)) {
					Slider(value: $engine.masterVolume, in: 0...1)
						.accessibilityLabel("Master Output Volume")
						.accessibilityValue("\(Int(engine.masterVolume * 100)) percent")
				}
				
				Section {
					Button(action: {
						engine.playStop()
					}) {
						Text(engine.isPlaying ? "Stop Audio" : "Synthesize & Play")
							.frame(maxWidth: .infinity, alignment: .center)
							.foregroundColor(engine.isPlaying ? .red : .blue)
					}
					.accessibilityLabel(engine.isPlaying ? "Stop Audio Playback" : "Synthesize and Play Real Time Audio")
					.accessibilityAddTraits(.isButton)
				}
			}
			.navigationTitle("ASMR Sleep Engine")
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