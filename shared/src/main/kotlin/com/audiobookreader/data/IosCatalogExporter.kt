package com.audiobookreader.data

import java.io.File

/** Keeps iOS and Android on one catalogue without bundling Android's custom PocketTTS runtime on iOS. */
object IosCatalogExporter {
    @JvmStatic
    fun main(args: Array<String>) {
        require(args.size == 1) { "Expected the output JSON path" }
        val output = File(args.single())
        output.parentFile.mkdirs()
        val models = ModelCatalog.models.filter { it.family != ModelFamily.POCKET }
        val json = buildString {
            append("[\n")
            models.forEachIndexed { index, model ->
                append("  {")
                field("id", model.id)
                field("name", model.name)
                field("family", model.family.name.lowercase())
                field("language", model.language)
                field("archiveURL", model.archiveName)
                field("modelName", model.modelName)
                field("voices", model.voices)
                field("lexicon", model.lexicon)
                field("ruleFsts", model.ruleFsts)
                field("ruleFars", model.ruleFars)
                field("dataDir", model.dataDir)
                field("storageId", model.storageId)
                field("auxiliaryURL", model.auxiliaryUrl)
                field("auxiliaryName", model.auxiliaryName)
                field("licenseSpdx", model.licenseSpdx)
                field("licenseURL", model.licenseUrl)
                field("attribution", model.attribution)
                append("\"requiresAcceptance\":${model.requiresAcceptance},")
                append("\"referenceAudioRequired\":${model.referenceAudioRequired},")
                append("\"referenceTextRequired\":${model.referenceTextRequired},")
                stringArray("requiredFiles", model.requiredFiles)
                append('}')
                if (index != models.lastIndex) append(',')
                append('\n')
            }
            append("]\n")
        }
        val temporary = File(output.parentFile, ".${output.name}.tmp")
        temporary.writeText(json)
        check(temporary.renameTo(output)) { "Unable to publish ${output.absolutePath}" }
    }

    private fun StringBuilder.field(name: String, value: String) {
        append('"').append(name).append("\":\"").append(value.jsonEscape()).append("\",")
    }

    private fun StringBuilder.stringArray(name: String, values: List<String>) {
        append('"').append(name).append("\":[")
        values.forEachIndexed { index, value ->
            if (index > 0) append(',')
            append('"').append(value.jsonEscape()).append('"')
        }
        append(']')
    }

    private fun String.jsonEscape(): String = buildString(length) {
        this@jsonEscape.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (character.code < 0x20) append("\\u%04x".format(character.code)) else append(character)
            }
        }
    }
}
