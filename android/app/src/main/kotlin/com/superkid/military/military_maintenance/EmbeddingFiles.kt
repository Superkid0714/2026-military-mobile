package com.superkid.military.military_maintenance

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

object EmbeddingFiles {
    const val EXECUTION_CONFIG = "ort1.23.2-all-cpu-u8s8-cased128-dense512-v1"
    private val names = setOf("model.onnx", "vocab.txt", "index.json", "knowledge.json", "LICENSE.txt", "manifest.json")
    fun active(context: Context) = File(context.filesDir, "rag/active")
    fun sha(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val n = input.read(buffer); if (n < 0) break; hash.update(buffer, 0, n) }
        }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    fun validate(directory: File, verifyCorpus: Boolean = true): JSONObject {
        val manifestFile = File(directory, "manifest.json")
        require(manifestFile.length() in 1..32768)
        val m = JSONObject(manifestFile.readText())
        require(m.getInt("version") in 1..2 && m.getString("modelId") == "distiluse-int8-v1")
        require(m.getInt("dimension") == 512 && m.getInt("maxTokens") == 128 && m.getInt("minAndroidApi") == 24)
        require(m.getString("license") == "Apache-2.0" && m.getString("runtime") == "onnxruntime-1.23.2-cpu")
        require(m.getString("executionConfig") == EXECUTION_CONFIG)
        val files = m.getJSONObject("files")
        val expected = names - "manifest.json" + if (m.getInt("version") == 2) setOf("corpus.sqlite") else emptySet()
        require(files.keys().asSequence().toSet() == expected)
        for (name in expected) {
            val file = File(directory, name)
            val spec = files.getJSONObject(name)
            require(file.isFile && file.length() == spec.getLong("bytes"))
            // Full corpus bytes are verified at atomic install. Model loading
            // checks app-private corpus identity/size, not all page-image bytes.
            if (name != "corpus.sqlite" || verifyCorpus) require(sha(file) == spec.getString("sha256"))
        }
        require(File(directory, "index.json").length() <= 4 * 1024 * 1024)
        require(File(directory, "knowledge.json").length() <= 4 * 1024 * 1024)
        require(File(directory, "vocab.txt").length() <= 4 * 1024 * 1024)
        if (m.getInt("version") == 2) {
            require(File(directory, "corpus.sqlite").length() in 1..(1024L * 1024 * 1024))
            val db = android.database.sqlite.SQLiteDatabase.openDatabase(File(directory,"corpus.sqlite").path,null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY)
            try {
                if (verifyCorpus) db.rawQuery("PRAGMA integrity_check",null).use { require(it.moveToFirst() && it.getString(0)=="ok") }
                val metadata = mutableMapOf<String,String>()
                db.rawQuery("SELECT key,value FROM metadata",null).use { while(it.moveToNext()) metadata[it.getString(0)]=it.getString(1) }
                require(metadata["version"]=="2" && metadata["dimension"]=="512" &&
                    metadata["executionConfig"]==EXECUTION_CONFIG && metadata["modelSha256"]==files.getJSONObject("model.onnx").getString("sha256"))
                if (metadata["imageFormat"] != null && verifyCorpus) {
                    require(metadata["imageFormat"]=="jpeg-pages-v1")
                    val count=metadata["imagePageCount"]!!.toInt()
                    require(count in 1..10000 && m.getJSONObject("corpus").getString("imagePageCount").toInt()==count)
                    db.rawQuery("SELECT count(*) FROM page_images",null).use {require(it.moveToFirst() && it.getInt(0)==count)}
                    db.rawQuery("SELECT count(*) FROM pages",null).use {require(it.moveToFirst() && it.getInt(0)==count)}
                    db.rawQuery("SELECT count(*) FROM page_images i LEFT JOIN pages p ON p.id=i.page_id WHERE p.id IS NULL OR i.width NOT BETWEEN 1 AND 1800 OR i.height NOT BETWEEN 1 AND 1800 OR length(i.jpeg) NOT BETWEEN 128 AND 2097152",null).use {require(it.moveToFirst() && it.getInt(0)==0)}
                }
            } finally { db.close() }
        }
        return m
    }
    fun install(context: Context, source: File): Map<String, Any> {
        require(source.canonicalPath.startsWith(context.cacheDir.canonicalPath + File.separator) && source.isFile)
        require(source.length() in 1..(1280L * 1024 * 1024))
        require(context.filesDir.usableSpace > maxOf(512L * 1024 * 1024, source.length() * 2 + 64L * 1024 * 1024))
        val parent = File(context.filesDir, "rag").apply { mkdirs() }
        val stage = File(parent, "staging-${System.nanoTime()}").apply { mkdir() }
        var total = 0L
        try {
            val seen = mutableSetOf<String>()
            ZipInputStream(source.inputStream().buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    require(!entry.isDirectory && entry.name in (names + "corpus.sqlite") && seen.add(entry.name))
                    File(stage, entry.name).outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val n = zip.read(buffer); if (n < 0) break
                            total += n; require(total <= 1536L * 1024 * 1024)
                            output.write(buffer, 0, n)
                        }
                    }
                }
            }
            val validated = validate(stage)
            require(seen == names + if (validated.getInt("version") == 2) setOf("corpus.sqlite") else emptySet())
            val active = active(context)
            val backup = File(parent, "previous-${System.nanoTime()}")
            if (active.exists()) check(active.renameTo(backup))
            if (!stage.renameTo(active)) { backup.renameTo(active); error("install_failed") }
            backup.deleteRecursively() // Fixed app-private sibling generated above.
            return info(context)
        } finally { stage.deleteRecursively() }
    }
    fun info(context: Context): Map<String, Any> {
        val dir = active(context)
        val file = File(dir, "manifest.json")
        if (!file.isFile) return mapOf("installed" to false)
        val m = JSONObject(file.readText())
        val result = mutableMapOf<String,Any>("installed" to true, "modelId" to m.getString("modelId"),
            "minAndroidApi" to m.getInt("minAndroidApi"), "indexPath" to File(dir, "index.json").path,
            "knowledgePath" to File(dir, "knowledge.json").path,
            "modelSha256" to m.getJSONObject("files").getJSONObject("model.onnx").getString("sha256"),
            "executionConfig" to m.getString("executionConfig"))
        if (m.getInt("version") == 2) {
            result["corpusDatabasePath"] = File(dir,"corpus.sqlite").path
            result["corpusSearchablePageCount"] = m.getJSONObject("corpus").optString("searchablePageCount",m.getJSONObject("corpus").getString("pageCount")).toInt()
            result["corpusImagePageCount"] = m.getJSONObject("corpus").optString("imagePageCount","0").toInt()
            result["corpusPageCount"] = m.getJSONObject("corpus").getString("pageCount").toInt()
            result["corpusDocumentCount"] = m.getJSONObject("corpus").getString("documentCount").toInt()
        }
        return result
    }
}
