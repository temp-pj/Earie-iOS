import ProjectDescription

/// 서버 계약 fixture. 복사하지 않고 명세 폴더를 테스트 리소스로 직접 참조한다 (tasks.md 10번).
let contractFixtures: ResourceFileElements = ["docs/specs/random-matchmaking/fixtures/*.json"]

/// `bundle exec fastlane test`가 실행하는 단위 테스트 타깃. 통합 테스트(SessionIntegrationTests)는 넣지 않는다.
let unitTestTargets: [TestableTarget] = [
    "ModelsTests",
    "ClientSessionTests",
    "ClientCatalogTests",
    "FeatureLobbyTests",
    "FeatureRoomTest",
    "M_GAMETests",
]

let project = Project(
    name: "M_GAME",
    targets: [
        .target(name: "Models",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.Models",
                sources: ["Models/Sources/**"]
               ),

            .target(name: "ModelsTests",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.ModelsTests",
                    sources: ["Models/Tests/**"],
                    resources: contractFixtures,
                    dependencies: [
                        .target(name: "Models")
                    ]
                   ),

            .target(name: "ClientSession",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientSession",
                    sources: ["Clients/SessionClient/Interface/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),

            .target(name: "ClientSessionLive",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientSessionLive",
                    sources: ["Clients/SessionClient/Live/Sources/**"],
                    dependencies: [
                        .target(name: "ClientSession"),
                        .target(name: "ClientWebSocket"),
                        .target(name: "ClientWebSocketLive"),
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),

            .target(name: "ClientSessionTest",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientSessionTest",
                    sources: ["Clients/SessionClient/Test/Sources/**"],
                    dependencies: [
                        .target(name: "ClientSession"),
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),

            .target(name: "ClientSessionTests",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.ClientSessionTests",
                    sources: ["Clients/SessionClient/Tests/**"],
                    resources: contractFixtures,
                    dependencies: [
                        .target(name: "ClientSessionLive"),
                        .target(name: "ClientSession"),
                        .target(name: "ClientWebSocket"),
                        .target(name: "Models")
                    ]
                   ),

            .target(name: "ClientCatalog",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientCatalog",
                    sources: ["Clients/CatalogClient/Interface/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),

            .target(name: "ClientCatalogLive",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientCatalogLive",
                    sources: ["Clients/CatalogClient/Live/Sources/**"],
                    dependencies: [
                        .target(name: "ClientCatalog"),
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),

            .target(name: "ClientCatalogTest",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientCatalogTest",
                    sources: ["Clients/CatalogClient/Test/Sources/**"],
                    dependencies: [
                        .target(name: "ClientCatalog"),
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),

            .target(name: "ClientCatalogTests",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.ClientCatalogTests",
                    sources: ["Clients/CatalogClient/Tests/**"],
                    resources: contractFixtures,
                    dependencies: [
                        .target(name: "ClientCatalogLive"),
                        .target(name: "ClientCatalog"),
                        .target(name: "Models")
                    ]
                   ),

            .target(name: "SessionIntegrationTests",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.SessionIntegrationTests",
                    sources: ["IntegrationTests/**"],
                    resources: contractFixtures,
                    dependencies: [
                        .target(name: "ClientSessionLive"),
                        .target(name: "ClientSession"),
                        .target(name: "Models")
                    ]
                   ),

            .target(name: "ClientAuth",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientAuth",
                    sources: ["Clients/AuthClient/Interface/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
            .target(name: "ClientAuthLive",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientAuthLive",
                    sources: ["Clients/AuthClient/Live/Sources/**"],
                    dependencies: [
                        .target(name: "ClientAuth"),
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
            .target(name: "ClientAuthTest",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientAuthTest",
                    sources: ["Clients/AuthClient/Test/Sources/**"],
                    dependencies: [
                        .target(name: "ClientAuth"),
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
        
        
        
        
        
        
            .target(name: "ClientWebSocket",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientWebSocket",
                    sources: ["Clients/WebSocketClient/Interface/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
        
            .target(name: "ClientWebSocketLive",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientWebSocketLive",
                    sources: ["Clients/WebSocketClient/Live/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .target(name: "ClientWebSocket"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
            .target(name: "ClientWebSocketTest",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientWebSocketTest",
                    sources: ["Clients/WebSocketClient/Test/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .target(name: "ClientWebSocket"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
        
        
            .target(
                name: "ClientMusicEntitlement",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.ClientMusicEntitlement",
                sources: ["Clients/MusicEntitlementClient/Interface/Sources/**"],
                dependencies: [
                    .target(name: "Models"),
                    .external(name: "ComposableArchitecture")
                ]
            ),
        
            .target(name: "ClientMusicEntitlementLive",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientMusicEntitlementLive",
                    sources: ["Clients/MusicEntitlementClient/Live/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .target(name: "ClientMusicEntitlement"),
                        .external(name: "ComposableArchitecture")
                    ]),
        
            .target(name: "ClientMusicEntitlementTest",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.ClientMusicEntitlementTest",
                    sources: ["Clients/MusicEntitlementClient/Test/Sources/**"],
                    dependencies: [
                        .target(name: "Models"),
                        .target(name: "ClientMusicEntitlement"),
                        .external(name: "ComposableArchitecture")
                    ]
                   ),
        
            .target(
                name: "ClientAudio",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.ClientAudio",
                sources: ["Clients/AudioClient/Interface/Sources/**"],
                dependencies: [
                    .target(name: "Models"),
                    .external(name: "ComposableArchitecture")
                ]
            ),
        
            .target(
                name: "ClientAudioLive",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.ClientAudioLive",
                sources: ["Clients/AudioClient/Live/Sources/**"],
                dependencies: [
                    .target(name: "Models"),
                    .target(name: "ClientAudio"),
                    .external(name: "ComposableArchitecture")
                ]
            ),
        
            .target(
                name: "ClientAudioTest",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.ClientAudioTest",
                sources: ["Clients/AudioClient/Test/Sources/**"],
                dependencies: [
                    .target(name: "Models"),
                    .target(name: "ClientAudio"),
                    .external(name: "ComposableArchitecture")
                ]
            ),
        
            .target(
                name: "FeatureLogin",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.FeatureLogin",
                sources: ["Features/Login/Sources/**"],
                dependencies: [
                    .target(name: "MDS"),
                    .target(name: "Models"),
                    .target(name: "ClientAuth"),
                    .external(name: "ComposableArchitecture")
                ]
            ),
        .target(
            name: "FeatureLobby",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.MGAME.FeatureLobby",
            sources: ["Features/Lobby/Sources/**"],
            dependencies: [
                .target(name: "MDS"),
                .target(name: "Models"),
                .target(name: "ClientCatalog"),
                .external(name: "ComposableArchitecture")
            ]
        ),

            .target(name: "FeatureLobbyTests",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.FeatureLobbyTests",
                    sources: ["Features/Lobby/Tests/**"],
                    resources: contractFixtures,
                    dependencies: [
                        .target(name: "FeatureLobby"),
                        .target(name: "ClientCatalogTest"),
                        .target(name: "Models")
                    ]
                   ),

            .target(
                name: "FeatureRoom",
                destinations: .iOS,
                product: .staticFramework,
                bundleId: "io.tuist.MGAME.FeatureRoom",
                sources: ["Features/Room/Sources/**"],
                dependencies: [
                    .target(name: "MDS"),
                    .target(name: "Models"),
                    .target(name: "ClientMusicEntitlement"),
                    .target(name: "ClientAudio"),
                    .external(name: "ComposableArchitecture")
                ]
            ),
        
            .target(name: "FeatureRoomTest",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.FeatureRoomTest",
                    sources: ["Features/Room/Tests/**"],
                    dependencies: [
                        .target(name: "FeatureRoom"),
                        .target(name: "ClientAudioTest"),
                        .target(name: "ClientMusicEntitlementTest")
                    ]
                   ),
        
            .target(name: "MDS",
                    destinations: .iOS,
                    product: .staticFramework,
                    bundleId: "io.tuist.MGAME.MDS",
                    sources: ["Shared/MDS/Sources/**"],
                    resources: ["Shared/MDS/Resources/**"]
                   ),
        
            .target(
                name: "M_GAME",
                destinations: .iOS,
                product: .app,
                bundleId: "io.tuist.M-GAME",
                infoPlist: .extendingDefault(
                    with: [
                        "UILaunchScreen": [
                            "UIColorName": "",
                            "UIImageName": "",
                        ],
                        "NSAppleMusicUsageDescription": "음악 퀴즈를 위해 Apple Music 접근이 필요합니다.",
                        "NSAppTransportSecurity": [
                            "NSAllowsArbitraryLoads": true
                        ],
                        "SERVER_HOST": "$(SERVER_HOST)"
                    ]
                ),
                sources: ["M_GAME/Sources/**"],
                resources: ["M_GAME/Resources/**"],
                dependencies: [
                    .target(name: "FeatureLogin"),
                    .target(name: "FeatureLobby"),
                    .target(name: "FeatureRoom"),
                    .target(name: "ClientAudioLive"),
                    .target(name: "ClientAuthLive"),
                    .target(name: "ClientMusicEntitlementLive"),
                    .target(name: "ClientSession"),
                    .target(name: "ClientSessionLive"),
                    .target(name: "ClientCatalog"),
                    .target(name: "ClientCatalogLive"),
                    .external(name: "ComposableArchitecture")
                ],
                settings: .settings(
                    configurations: [
                        .debug(name: "Debug", xcconfig: "Configs/Secrets.xcconfig"),
                        .release(name: "Release", xcconfig: "Configs/Secrets.xcconfig"),
                    ]
                    )
            ),

            .target(name: "M_GAMETests",
                    destinations: .iOS,
                    product: .unitTests,
                    bundleId: "io.tuist.MGAME.M-GAMETests",
                    sources: ["M_GAME/Tests/**"],
                    resources: contractFixtures,
                    dependencies: [
                        .target(name: "M_GAME"),
                        .target(name: "ClientSessionTest"),
                        .target(name: "ClientCatalogTest"),
                        .target(name: "ClientAudioTest"),
                        .target(name: "ClientMusicEntitlementTest")
                    ]
                   ),
    ],
    schemes: [
        .scheme(
            name: "M_GAME-UnitTests",
            shared: true,
            buildAction: .buildAction(targets: unitTestTargets.map(\.target)),
            testAction: .targets(unitTestTargets)
        ),
    ]
)
