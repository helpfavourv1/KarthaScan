import UIKit
import Flutter
import Vision

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.zdmgold.katharscan/tess_ocr",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        VisionOcr.handle(call, result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

/// Reads Arabic, Russian, Ukrainian, Greek, Hebrew, Thai and Bengali with
/// Apple's Vision framework (same channel and reply shape as the Android
/// Tesseract reader). Languages this iOS version cannot read report "unsupported".
enum VisionOcr {
  static let languages: [String: String] = [
    "ara": "ar-SA", "rus": "ru-RU", "ukr": "uk-UA", "ell": "el-GR",
    "heb": "he-IL", "tha": "th-TH", "ben": "bn-IN",
  ]

  private static func makeRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(iOS 16.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
    }
    return request
  }

  static func supports(_ code: String) -> Bool {
    guard let language = languages[code] else { return false }
    guard let supported = try? makeRequest().supportedRecognitionLanguages() else { return false }
    return supported.contains(language)
  }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let code = args["language"] as? String ?? ""
    switch call.method {
    case "supports":
      result(supports(code))
    case "extract":
      guard supports(code), let language = languages[code] else {
        result(FlutterError(code: "unsupported", message: "Language not supported by this iOS version", details: nil))
        return
      }
      guard let path = args["imagePath"] as? String,
            let image = UIImage(contentsOfFile: path),
            let cgImage = image.cgImage else {
        result(FlutterError(code: "bad_image", message: "Could not read the image", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let request = makeRequest()
        request.recognitionLanguages = [language]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
          try handler.perform([request])
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "failed", message: "\(error)", details: nil)) }
          return
        }
        let width = Double(cgImage.width)
        let height = Double(cgImage.height)
        var lines: [[String: Any]] = []
        var all: [String] = []
        for observation in (request.results ?? []) {
          guard let candidate = observation.topCandidates(1).first else { continue }
          let box = observation.boundingBox  // normalised, origin bottom-left
          lines.append([
            "text": candidate.string,
            "left": box.minX * width,
            "top": (1.0 - box.maxY) * height,
            "width": box.width * width,
            "height": box.height * height,
            "confidence": Double(candidate.confidence) * 100.0,
          ])
          all.append(candidate.string)
        }
        DispatchQueue.main.async { result(["text": all.joined(separator: "\n"), "lines": lines]) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
