import Foundation

import AgentPanelCLICore
import AgentPanelCore

let args = Array(CommandLine.arguments.dropFirst())
let cli = ApCLI(
    parser: ApArgumentParser(),
    dependencies: ApCLIDependencies(
        version: { AgentPanel.version },
        configLoader: { ConfigLoader.loadDefault() },
        coreFactory: { ApCore(config: $0) },
        doctorRunner: {
            Doctor(runningApplicationChecker: AppKitRunningApplicationChecker()).run()
        }
    ),
    output: .standard
)
exit(cli.run(arguments: args))
