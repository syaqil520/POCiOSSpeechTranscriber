import ProjectDescription

let project = Project(
    name: "POCiOSSpeechTranscriber",
    targets: [
        .target(
            name: "POCiOSSpeechTranscriber",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.POCiOSSpeechTranscriber",
            deploymentTargets: .iOS("15.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSMicrophoneUsageDescription": "We need access to your microphone to transcribe your speech.",
                    "NSSpeechRecognitionUsageDescription": "We need speech recognition to convert your voice to text.",
                ]
            ),
            buildableFolders: [
                "POCiOSSpeechTranscriber/Sources",
                "POCiOSSpeechTranscriber/Resources",
            ],
            dependencies: [
            ]
        ),
        .target(
            name: "POCiOSSpeechTranscriberTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.POCiOSSpeechTranscriberTests",
            deploymentTargets: .iOS("15.0"),
            infoPlist: .default,
            buildableFolders: [
                "POCiOSSpeechTranscriber/Tests"
            ],
            dependencies: [.target(name: "POCiOSSpeechTranscriber")]
        ),
    ]
)
