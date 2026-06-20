import SwiftUI
import AVFoundation

class HeartRateMonitor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
	@Published var isMeasuring = false
	@Published var currentBPM: Double = 0
	@Published var progress: Double = 0
	@Published var error: String?

	private var captureSession: AVCaptureSession?
	private var videoDevice: AVCaptureDevice?
	
	private var frameCounter = 0
	private var redValues = [Double]()
	private var timestamps = [Double]()
	private var startTime: Double = 0
	
	func startMeasurement() {
		isMeasuring = true
		progress = 0
		currentBPM = 0
		error = nil
		redValues.removeAll()
		timestamps.removeAll()
		frameCounter = 0
		
		setupCaptureSession()
	}
	
	func stopMeasurement() {
		captureSession?.stopRunning()
		turnOffFlashlight()
		isMeasuring = false
	}
	
	private func setupCaptureSession() {
		let session = AVCaptureSession()
		session.sessionPreset = .low
		
		guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
			DispatchQueue.main.async { self.error = String(localized: "No back camera available.") }
			return
		}
		self.videoDevice = device
		
		do {
			let input = try AVCaptureDeviceInput(device: device)
			if session.canAddInput(input) { session.addInput(input) }
			
			let output = AVCaptureVideoDataOutput()
			output.alwaysDiscardsLateVideoFrames = true
			let queue = DispatchQueue(label: "videoQueue")
			output.setSampleBufferDelegate(self, queue: queue)
			
			output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
			if session.canAddOutput(output) { session.addOutput(output) }
			
			try device.lockForConfiguration()
			if device.hasTorch && device.isTorchAvailable {
				device.torchMode = .on
				try device.setTorchModeOn(level: 1.0)
			}
			device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
			device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
			device.unlockForConfiguration()
			
			self.captureSession = session
			
			DispatchQueue.global(qos: .userInitiated).async {
				session.startRunning()
				self.startTime = CACurrentMediaTime()
			}
		} catch let e {
			DispatchQueue.main.async { self.error = e.localizedDescription }
		}
	}
	
	private func turnOffFlashlight() {
		guard let device = videoDevice else { return }
		do {
			try device.lockForConfiguration()
			if device.hasTorch { device.torchMode = .off }
			device.unlockForConfiguration()
		} catch {}
	}
	
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
		
		CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
		let width = CVPixelBufferGetWidth(imageBuffer)
		let height = CVPixelBufferGetHeight(imageBuffer)
		guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
			CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
			return
		}
		
		let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
		var totalRed: UInt64 = 0
		let pixelCount = width * height
		
		for i in stride(from: 0, to: pixelCount * 4, by: 4) {
			totalRed += UInt64(buffer[i + 2])
		}
		
		CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
		
		let avgRed = Double(totalRed) / Double(pixelCount)
		let now = CACurrentMediaTime()
		
		DispatchQueue.main.async {
			self.processFrame(redValue: avgRed, timestamp: now)
		}
	}
	
	private func processFrame(redValue: Double, timestamp: Double) {
		redValues.append(redValue)
		timestamps.append(timestamp)
		
		let elapsed = timestamp - startTime
		progress = min(1.0, elapsed / 10.0)
		
		if elapsed >= 10.0 {
			calculateBPM()
			stopMeasurement()
		}
	}
	
	private func calculateBPM() {
		guard redValues.count > 30 else {
			error = String(localized: "Not enough data.")
			return
		}
		
		var smoothed = [Double]()
		let window = 5
		for i in 0..<(redValues.count - window) {
			let avg = redValues[i..<(i+window)].reduce(0, +) / Double(window)
			smoothed.append(avg)
		}
		
		let mean = smoothed.reduce(0, +) / Double(smoothed.count)
		let detrended = smoothed.map { $0 - mean }
		
		var peaks = 0
		var inPeak = false
		for val in detrended {
			if val > 0 && !inPeak {
				inPeak = true
				peaks += 1
			} else if val < 0 {
				inPeak = false
			}
		}
		
		let duration = timestamps.last! - timestamps.first!
		let bpm = Double(peaks) / duration * 60.0
		
		if bpm > 40 && bpm < 200 {
			self.currentBPM = bpm
		} else {
			self.error = String(localized: "Could not detect a clear pulse. Make sure your finger fully covers the lens and flash.")
		}
	}
}

struct CameraHeartRateMonitorView: View {
	@StateObject private var monitor = HeartRateMonitor()
	@Binding var isPresented: Bool
	@Binding var enableCustomBPM: Bool
	@Binding var customBPM: Double
	@Binding var enableSlowdown: Bool
	@Binding var targetBPM: Double
	
	var body: some View {
		NavigationView {
			VStack(spacing: 30) {
				Text("Camera Heart Rate Sync")
					.font(.title2).bold()
					.accessibilityAddTraits(.isHeader)
				
				Text("Put your finger over the main camera lens (usually the top or bottom left lens on the back, closest to the flash). Make sure you also cover the flashlight so the light illuminates your finger.")
					.multilineTextAlignment(.center)
					.padding(.horizontal)
				
				if monitor.isMeasuring {
					ProgressView(value: monitor.progress)
						.padding()
						.accessibilityLabel("Measurement progress")
						.accessibilityValue("\(Int(monitor.progress * 100)) percent")
					
					Text("Detecting pulse...")
						.font(.headline)
						.accessibilityLabel("Detecting pulse, please hold still")
				} else if monitor.currentBPM > 0 {
					Text("\(Int(monitor.currentBPM)) BPM")
						.font(.system(size: 64, weight: .bold, design: .rounded))
						.foregroundColor(.red)
						.accessibilityLabel("Detected heart rate: \(Int(monitor.currentBPM)) beats per minute")
					
					Button(action: {
						customBPM = monitor.currentBPM
						enableCustomBPM = true
						if !enableSlowdown {
							targetBPM = max(40, customBPM - 10)
							enableSlowdown = true
						} else {
							if targetBPM > customBPM {
								targetBPM = max(40, customBPM - 10)
							}
						}
						isPresented = false
					}) {
						Text("Use This Heart Rate")
							.font(.headline)
							.foregroundColor(.white)
							.padding()
							.frame(maxWidth: .infinity)
							.background(Color.blue)
							.cornerRadius(12)
					}
					.padding(.horizontal)
				} else if let error = monitor.error {
					Text(error)
						.foregroundColor(.red)
						.multilineTextAlignment(.center)
						.padding()
						.accessibilityLabel("Error: \(error)")
					
					Button("Try Again") {
						monitor.startMeasurement()
					}
					.padding()
				}
				
				Spacer()
			}
			.padding(.top, 40)
			.navigationBarItems(trailing: Button("Cancel") {
				monitor.stopMeasurement()
				isPresented = false
			})
			.onAppear {
				monitor.startMeasurement()
			}
			.onDisappear {
				monitor.stopMeasurement()
			}
		}
	}
}
