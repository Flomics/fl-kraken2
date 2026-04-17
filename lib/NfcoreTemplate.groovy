//
// Utility functions for the Flomics/fl-phylo pipeline.
// Stripped to logo-related helpers only (no email / IM / schema deps).
//

class NfcoreTemplate {

    //
    // Generate version string
    //
    public static String version(workflow) {
        String version_string = ""

        if (workflow.manifest.version) {
            def prefix_v = workflow.manifest.version[0] != 'v' ? 'v' : ''
            version_string += "${prefix_v}${workflow.manifest.version}"
        }

        if (workflow.commitId) {
            def git_shortsha = workflow.commitId.substring(0, 7)
            version_string += "-g${git_shortsha}"
        }

        return version_string
    }

    //
    // ANSII Colours used for terminal logging
    //
    public static Map logColours(Boolean monochrome_logs) {
        Map colorcodes = [:]

        // Reset / Meta
        colorcodes['reset']      = monochrome_logs ? '' : "\033[0m"
        colorcodes['bold']       = monochrome_logs ? '' : "\033[1m"
        colorcodes['dim']        = monochrome_logs ? '' : "\033[2m"

        // Regular Colors
        colorcodes['red']        = monochrome_logs ? '' : "\033[0;31m"
        colorcodes['green']      = monochrome_logs ? '' : "\033[0;32m"
        colorcodes['yellow']     = monochrome_logs ? '' : "\033[0;33m"
        colorcodes['purple']     = monochrome_logs ? '' : "\033[0;35m"
        colorcodes['cyan']       = monochrome_logs ? '' : "\033[0;36m"

        return colorcodes
    }

    //
    // Dashed separator line
    //
    public static String dashedLine(monochrome_logs) {
        Map colors = logColours(monochrome_logs)
        return "-${colors.dim}----------------------------------------------------${colors.reset}-"
    }

    //
    // fl-phylo logo (octopus)
    //
    public static String logo(workflow, monochrome_logs) {
        Map colors = logColours(monochrome_logs)
        String workflow_version = NfcoreTemplate.version(workflow)
        String.format(
            """\n
            ${dashedLine(monochrome_logs)}
            ${colors.purple}                                    ___                                 ${colors.reset}
            ${colors.purple}                                 .-'   `'.                              ${colors.reset}
            ${colors.purple}                                /         \\                            ${colors.reset}
            ${colors.purple}                                |         ;                             ${colors.reset}
            ${colors.purple}                                |         |           ___.--,           ${colors.reset}
            ${colors.purple}                       _.._     |0) ~ (0) |    _.---'`__.-( (_.         ${colors.reset}
            ${colors.purple}                __.--'`_.. '.__.\\    '--. \\_.-' ,.--'`     `""`       ${colors.reset}
            ${colors.purple}               ( ,.--'`   ',__ /./;   ;, '.__.'`    __                  ${colors.reset}
            ${colors.purple}               _`) )  .---.__.' / |   |\\   \\__..--""  ""*--.,_        ${colors.reset}
            ${colors.purple}              `---' .'.''-._.-'`_./  /\\ '.  \\ _.-~~~````~~~-._`-.__.' ${colors.reset}
            ${colors.purple}                    | |  .' _.-' |  |  \\  \\  '.               `~---`  ${colors.reset}
            ${colors.purple}                     \\ \\/ .'     \\  \\   '. '-._)                    ${colors.reset}
            ${colors.purple}                      \\/ /        \\  \\    `=.__`~-.                  ${colors.reset}
            ${colors.purple}                      / /\\         `) )    / / `"".`\\                 ${colors.reset}
            ${colors.purple}                , _.-'.'\\ \\        / /    ( (     / /                 ${colors.reset}
            ${colors.purple}                 `--~`   ) )    .-'.'      '.'.  ( (                    ${colors.reset}
            ${colors.purple}                        (/`    ( (`          ) )  '-;                   ${colors.reset}
            ${colors.purple}                         `      '-;         (-'                         ${colors.reset}
            ${colors.purple}  ${workflow.manifest.name} ${workflow_version}${colors.reset}
            ${dashedLine(monochrome_logs)}
            """.stripIndent()
        )
    }
}
