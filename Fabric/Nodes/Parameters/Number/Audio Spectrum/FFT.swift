//
//  FFT.swift
//  Spectra
//
//  Created by Reza Ali on 4/3/20.
//  Copyright © 2020 Hi-Rez, Inc. All rights reserved.
//

import Accelerate

final class FFT {
    public enum WindowSequence {
        case hanningNormalized
        case hanningDenormalized
        case hamming
        case blackman
        case none
    }

    public var windowSequence: FFT.WindowSequence = .blackman {
        didSet {
            setupWindow()
        }
    }

    public var smoothing: Float = 0.0

    private var samples: Int = 0
    private var n: Int = 0
    private var nOver2: Int = 0
    private var log2n: vDSP_Length = 0

    private var fftSetup: FFTSetup!

    private var window: [Float] = []
    private var windowedSignal: [Float] = []
    private var realParts: [Float] = []
    private var imagParts: [Float] = []
    private var spectrum: [Float] = []
    private var spectrumSmooth: [Float] = []

    public init?(samples: Int, windowSequence: FFT.WindowSequence = .blackman, smoothing: Float = 0.0) {
        let lg2 = logbf(Float(samples))
        if remainderf(Float(samples), powf(2.0, lg2)) != 0 {
            print("Number of samples is not a power of two: \(samples)")
            return nil
        }

        self.samples = samples
        self.windowSequence = windowSequence
        self.smoothing = smoothing
        setup()
    }

    private func setup() {
        n = samples
        nOver2 = n / 2
        log2n = vDSP_Length(log2(Float(n)))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to create FFT Setup")
        }

        fftSetup = setup

        setupBuffers()
        setupWindow()
    }

    private func setupBuffers() {
        realParts = [Float](repeating: 0, count: nOver2)
        imagParts = [Float](repeating: 0, count: nOver2)
        spectrum = [Float](repeating: 0, count: nOver2)
        spectrumSmooth = [Float](repeating: 0, count: nOver2)
        windowedSignal = [Float](repeating: 0, count: n)
        window = [Float](repeating: 1, count: n)
    }

    private func setupWindow() {
        switch windowSequence {
            case .blackman:
                vDSP_blkman_window(&window, vDSP_Length(n), 0)
            case .hamming:
                vDSP_hamm_window(&window, vDSP_Length(n), 0)
            case .hanningDenormalized:
                vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
            case .hanningNormalized:
                vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
            case .none:
                window = [Float](repeating: 1, count: n)
        }
    }

    public func forward(_ signal: UnsafeMutablePointer<Float>) {
        // Window Signal
        window.withUnsafeMutableBufferPointer { windowPtr in
            windowedSignal.withUnsafeMutableBufferPointer { windowedSignalPtr in
                vDSP_vmul(signal, 1, windowPtr.baseAddress!, 1, windowedSignalPtr.baseAddress!, 1, vDSP_Length(n))
            }
        }

        _forward()
    }

    public func forward(_ signal: [Float]) {
        // Window Signal
        window.withUnsafeMutableBufferPointer { windowPtr in
            windowedSignal.withUnsafeMutableBufferPointer { windowedSignalPtr in
                vDSP_vmul(signal, 1, windowPtr.baseAddress!, 1, windowedSignalPtr.baseAddress!, 1, vDSP_Length(n))
            }
        }

        _forward()
    }

    private func _forward() {
        spectrum.withUnsafeMutableBufferPointer { specPtr in
            realParts.withUnsafeMutableBufferPointer { realPtr in
                imagParts.withUnsafeMutableBufferPointer { imagPtr in
                    windowedSignal.withUnsafeMutableBufferPointer { winPtr in
                        winPtr.baseAddress?.withMemoryRebound(to: DSPComplex.self, capacity: nOver2) { complexPtr in
                            let n2 = vDSP_Length(nOver2)

                            // Create a DSPSplitComplex to contain the signal.
                            var complexSignal = DSPSplitComplex(realp: realPtr.baseAddress!,
                                                                imagp: imagPtr.baseAddress!)

                            // Convert complex to split complex signal
                            vDSP_ctoz(complexPtr, 2, &complexSignal, 1, n2)

                            // Forward FFT
                            vDSP_fft_zrip(fftSetup, &complexSignal, 1, log2n, FFTDirection(FFT_FORWARD))

                            // Process signal square root of the absolute value of each element of imagParts.
                            vDSP_zvmags(&complexSignal, 1, specPtr.baseAddress!, 1, n2)

                            // vDSP_zvmagsD returns squares of the FFT magnitudes, so take the root here
                            var len = Int32(nOver2)
                            vvsqrtf(specPtr.baseAddress!, specPtr.baseAddress!, &len)

                            // Scale to get into a good 0 - 1 range
                            var scalar: [Float] = [8.0 / Float(nOver2)]
                            vDSP_vsmul(specPtr.baseAddress!, 1, &scalar, specPtr.baseAddress!, 1, n2)
                        }
                    }
                }
            }
        }

        if smoothing > 0.0 {
            spectrum.withUnsafeMutableBufferPointer { specPtr in
                spectrumSmooth.withUnsafeMutableBufferPointer { specSmoothPtr in
                    let n2 = vDSP_Length(nOver2)
                    vDSP_vsmul(specSmoothPtr.baseAddress!, 1, &smoothing, specSmoothPtr.baseAddress!, 1, n2)
                    vDSP_vmaxmg(specPtr.baseAddress!, 1, specSmoothPtr.baseAddress!, 1, specSmoothPtr.baseAddress!, 1, n2)
                }
            }
        }
    }

    public func getSpectrum() -> [Float] {
        if smoothing > 0.0 {
            return spectrumSmooth
        }
        return spectrum
    }

    public func getReal() -> [Float] {
        return realParts
    }

    public func getImaginary() -> [Float] {
        return imagParts
    }

    public func getWindow() -> [Float] {
        return window
    }

    deinit {}
}
