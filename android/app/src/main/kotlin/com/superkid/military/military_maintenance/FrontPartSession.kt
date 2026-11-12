package com.superkid.military.military_maintenance

import android.content.Context
import android.graphics.Bitmap
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.nio.FloatBuffer
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.roundToInt
import org.json.JSONArray
import org.json.JSONObject

/** Locates possible part positions. A person must confirm the position and inspection result. */
internal class FrontPartSession(private val context: Context, threads: Int) : NativeModelSession {
    private val environment = OrtEnvironment.getEnvironment()
    private val session: OrtSession

    init {
        val model = context.assets.open(ASSET).use { it.readBytes() }
        val digest = MessageDigest.getInstance("SHA-256").digest(model)
        require(digest.joinToString("") { "%02x".format(it) } == SHA)
        session = OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(threads)
            options.setInterOpNumThreads(1)
            environment.createSession(model, options)
        }
    }

    override fun infer(inputJson: String): String {
        val image = File(JSONObject(inputJson).getString("imagePath"))
        val rgb = withVisionBitmap(context, image, 1200, ::pixels)
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(rgb), longArrayOf(1, 3, SIZE.toLong(), SIZE.toLong())).use { input ->
            session.run(mapOf("image" to input)).use { output ->
                @Suppress("UNCHECKED_CAST")
                val scores = (output.get("scores").get().value as Array<FloatArray>).single()
                @Suppress("UNCHECKED_CAST")
                val boxes = (output.get("boxes").get().value as Array<Array<FloatArray>>).single()
                require(scores.size == PARTS.size && boxes.size == PARTS.size)
                val proposals = JSONArray()
                for (i in PARTS.indices) {
                    val score = scores[i]
                    val box = boxes[i]
                    if (!score.isFinite() || score !in .25f..1f || box.size != 4 ||
                        box.any { !it.isFinite() || it !in 0f..1f } || box[2] == 0f || box[3] == 0f) continue
                    val (x, y, width, height) = box
                    proposals.put(JSONObject()
                        .put("part", PARTS[i])
                        .put("score", score.toDouble())
                        .put("box", JSONArray(listOf(
                            (x - width / 2).coerceAtLeast(0f),
                            (y - height / 2).coerceAtLeast(0f),
                            (x + width / 2).coerceAtMost(1f),
                            (y + height / 2).coerceAtMost(1f)
                        ))))
                }
                return JSONObject().put("modelId", ID).put("proposals", proposals).toString()
            }
        }
    }

    // Use the same separable antialiased bilinear filter as the training image loader.
    private fun pixels(bitmap: Bitmap): FloatArray {
        val width = bitmap.width
        val height = bitmap.height
        val argb = IntArray(width * height)
        bitmap.getPixels(argb, 0, width, 0, 0, width, height)
        val horizontal = IntArray(SIZE * height)
        for (y in 0 until height) {
            for (x in 0 until SIZE) {
                horizontal[y * SIZE + x] = filter(argb, y * width, 1, width, x)
            }
        }
        val plane = SIZE * SIZE
        val rgb = FloatArray(3 * plane)
        for (y in 0 until SIZE) {
            for (x in 0 until SIZE) {
                val value = filter(horizontal, x, SIZE, height, y)
                val i = y * SIZE + x
                rgb[i] = ((value ushr 16) and 255) / 255f
                rgb[i + plane] = ((value ushr 8) and 255) / 255f
                rgb[i + 2 * plane] = (value and 255) / 255f
            }
        }
        return rgb
    }

    private fun filter(pixels: IntArray, offset: Int, stride: Int, length: Int, index: Int): Int {
        val scale = length.toDouble() / SIZE
        val radius = scale.coerceAtLeast(1.0)
        val center = (index + .5) * scale
        val first = floor(center - radius + .5).toInt().coerceAtLeast(0)
        val last = floor(center + radius + .5).toInt().coerceAtMost(length)
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var total = 0.0
        for (i in first until last) {
            val weight = (1 - abs(i + .5 - center) / radius).coerceAtLeast(0.0)
            val pixel = pixels[offset + i * stride]
            red += weight * ((pixel ushr 16) and 255)
            green += weight * ((pixel ushr 8) and 255)
            blue += weight * (pixel and 255)
            total += weight
        }
        return ((red / total).roundToInt() shl 16) or
            ((green / total).roundToInt() shl 8) or (blue / total).roundToInt()
    }

    override fun close() = session.close()

    companion object {
        const val ID = "rexton-front-parts-v2"
        private const val SIZE = 192
        private const val ASSET = "front-vision/rexton-front-parts-v2.onnx"
        private const val SHA = "41418b160aa44f76b634112677468c09001454d362b8547a571b53e4f8f5e763"
        private val PARTS = listOf("hood", "leftLamp", "grille", "rightLamp", "bumper")

        fun info(context: Context): Map<String, Any> = mapOf(
            "modelId" to ID,
            "installed" to (context.assets.list("front-vision")?.contains(ASSET.substringAfter('/')) == true),
            "minAndroidApi" to 24,
            "sha256" to SHA
        )
    }
}
