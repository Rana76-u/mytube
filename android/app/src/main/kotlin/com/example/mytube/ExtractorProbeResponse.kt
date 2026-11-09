package com.example.mytube

internal object ExtractorProbeResponse {
    fun json(exitCode: Int, stdout: String?, stderr: String?): String {
        if (exitCode != 0) {
            val detail = stderr?.takeIf { it.isNotBlank() }
                ?: stdout?.takeIf { it.isNotBlank() }
                ?: "extractor probe failed (exit code $exitCode)"
            throw IllegalStateException(detail)
        }
        return stdout.orEmpty()
    }
}
