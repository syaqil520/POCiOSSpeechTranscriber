import ProjectDescription

let project = Project(
    name: "POCiOSSpeechTranscriber",
    targets: [
        .target(
            name: "POCiOSSpeechTranscriber",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.POCiOSSpeechTranscriber",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            buildableFolders: [
                "POCiOSSpeechTranscriber/Sources",
                "POCiOSSpeechTranscriber/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "POCiOSSpeechTranscriberTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.POCiOSSpeechTranscriberTests",
            infoPlist: .default,
            buildableFolders: [
                "POCiOSSpeechTranscriber/Tests"
            ],
            dependencies: [.target(name: "POCiOSSpeechTranscriber")]
        ),
    ]
)
