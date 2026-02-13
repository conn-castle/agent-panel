import Foundation

import AgentPanelAppKit
import AgentPanelCLICore
import AgentPanelCore

let args = Array(CommandLine.arguments.dropFirst())
let cli = ApCLI(
    parser: ApArgumentParser(),
    dependencies: ApCLIDependencies(
        version: { AgentPanel.version },
        projectManagerFactory: {
            ProjectManager(
                windowPositioner: AXWindowPositioner(),
                screenModeDetector: ScreenModeDetector()
            )
        },
        doctorRunner: {
            Doctor(
                runningApplicationChecker: AppKitRunningApplicationChecker(),
                windowPositioner: AXWindowPositioner()
            ).run()
        }
    ),
    output: .standard
)
exit(cli.run(arguments: args))
