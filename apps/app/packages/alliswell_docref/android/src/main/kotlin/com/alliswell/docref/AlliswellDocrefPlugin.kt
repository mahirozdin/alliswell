package com.alliswell.docref

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.security.MessageDigest

/**
 * The Android half of ADR-0030.
 *
 * Deliberately dumb, with the one stated exception: the expected-hash check
 * happens here, immediately before the write, because that is as close to
 * atomic as SAF allows.
 *
 * Declares NO permissions. SAF is permissionless by design, and
 * `scripts/android/assert-permissions.sh` proves it from the built APK.
 */
class AlliswellDocrefPlugin :
    FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener, PluginRegistry.NewIntentListener {

  private lateinit var channel: MethodChannel
  private var resolver: ContentResolver? = null
  private var activity: Activity? = null
  private var pendingPick: MethodChannel.Result? = null
  private var pendingMaxBytes = 0

  /** A document the OS opened before Dart was listening (ACTION_VIEW/EDIT). */
  private var pendingOpen: String? = null

  private companion object {
    const val PICK_REQUEST = 0xD0C1
    const val MAX_RECOVERY_BYTES = 4 * 1024 * 1024
  }

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    resolver = binding.applicationContext.contentResolver
    channel = MethodChannel(binding.binaryMessenger, "alliswell/docref")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    resolver = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addActivityResultListener(this)
    binding.addOnNewIntentListener(this)
    // The launch intent is already here; there is no callback for the one that
    // started us.
    rememberIfDocument(binding.activity.intent)
  }

  override fun onDetachedFromActivity() { activity = null }
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
      onAttachedToActivity(binding)
  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onNewIntent(intent: Intent): Boolean {
    rememberIfDocument(intent)
    return false
  }

  private fun rememberIfDocument(intent: Intent?) {
    val action = intent?.action ?: return
    if (action != Intent.ACTION_VIEW && action != Intent.ACTION_EDIT) return
    val uri = intent.data ?: return
    // Take the grant NOW: the one that came with the intent dies with the task,
    // and a recents entry that cannot reopen is the thing W6 exists to prevent.
    takePersistable(uri)
    pendingOpen = uri.toString()
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != PICK_REQUEST) return false
    val result = pendingPick ?: return true
    pendingPick = null
    val uri = data?.data
    if (resultCode != Activity.RESULT_OK || uri == null) {
      result.success(mapOf("refused" to "cancelled"))
      return true
    }
    takePersistable(uri)
    result.success(read(uri, pendingMaxBytes))
    return true
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
    when (call.method) {
      "pickExternal" -> pickExternal(call.argument<Int>("maxBytes") ?: 0, result)
      "open" ->
          result.success(
              read(Uri.parse(call.argument<String>("token")), call.argument<Int>("maxBytes") ?: 0))
      "adopt" -> {
        val uri = Uri.parse(call.argument<String>("osToken"))
        takePersistable(uri)
        result.success(read(uri, call.argument<Int>("maxBytes") ?: 0))
      }
      "probe" -> result.success(probe(Uri.parse(call.argument<String>("token"))))
      "save" ->
          result.success(
              save(
                  Uri.parse(call.argument<String>("token")),
                  call.argument<ByteArray>("bytes"),
                  call.argument<String>("expectedSha256") ?: "",
                  call.argument<Boolean>("force") ?: false))
      "clipboardRead" -> result.success(clipboardRead())
      "takeOpenedDocument" -> {
        val token = pendingOpen
        pendingOpen = null
        result.success(token?.let { mapOf("osToken" to it) })
      }
      else -> result.notImplemented()
    }
  }

  // ── Picking ────────────────────────────────────────────────────────────────

  private fun pickExternal(maxBytes: Int, result: MethodChannel.Result) {
    val current = activity
    if (current == null) {
      result.success(mapOf("refused" to "denied"))
      return
    }
    pendingPick = result
    pendingMaxBytes = maxBytes
    // ACTION_OPEN_DOCUMENT, not GET_CONTENT: only the former can hand back a
    // URI whose grant survives a reboot.
    val intent =
        Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
          addCategory(Intent.CATEGORY_OPENABLE)
          type = "*/*"
          putExtra(
              Intent.EXTRA_MIME_TYPES,
              arrayOf("text/markdown", "text/x-markdown", "text/plain", "application/octet-stream"))
          addFlags(
              Intent.FLAG_GRANT_READ_URI_PERMISSION or
                  Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                  Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
    current.startActivityForResult(intent, PICK_REQUEST)
  }

  /** Best effort: a provider that refuses write is a legitimate read-only file. */
  private fun takePersistable(uri: Uri) {
    val flags =
        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    try {
      resolver?.takePersistableUriPermission(uri, flags)
    } catch (e: SecurityException) {
      try {
        resolver?.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
      } catch (e2: SecurityException) {
        // Neither grant is persistable — the session grant still works, and
        // probe() will report what we actually hold.
      }
    }
  }

  // ── Reading ────────────────────────────────────────────────────────────────

  private fun read(uri: Uri, maxBytes: Int): Map<String, Any?> {
    val resolver = this.resolver ?: return mapOf("refused" to "gone")
    val meta = query(uri) ?: return mapOf("refused" to "gone")
    if (maxBytes > 0 && meta.size != null && meta.size > maxBytes) {
      return mapOf("refused" to "tooLarge")
    }
    val bytes =
        try {
          resolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
          null
        }
            ?: return mapOf("refused" to "denied")
    if (maxBytes > 0 && bytes.size > maxBytes) return mapOf("refused" to "tooLarge")

    return mapOf(
        "token" to uri.toString(),
        "kind" to "androidUri",
        "name" to (meta.name ?: uri.lastPathSegment ?: "document.md"),
        "bytes" to bytes,
        "writable" to (holdsWrite(uri) && meta.providerWritable),
        "modifiedAtMs" to meta.modifiedAtMs)
  }

  private class Meta(
      val name: String?,
      val size: Int?,
      val modifiedAtMs: Long?,
      val providerWritable: Boolean
  )

  private fun query(uri: Uri): Meta? {
    val resolver = this.resolver ?: return null
    val columns =
        arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS)
    val cursor: Cursor =
        try {
          resolver.query(uri, columns, null, null, null)
        } catch (e: Exception) {
          null
        }
            ?: return null
    cursor.use {
      if (!it.moveToFirst()) return null
      fun idx(name: String) = it.getColumnIndex(name).takeIf { i -> i >= 0 }
      val name = idx(DocumentsContract.Document.COLUMN_DISPLAY_NAME)?.let { i ->
        if (it.isNull(i)) null else it.getString(i)
      }
      val size = idx(DocumentsContract.Document.COLUMN_SIZE)?.let { i ->
        if (it.isNull(i)) null else it.getInt(i)
      }
      // COLUMN_LAST_MODIFIED is OPTIONAL in the SAF contract and cloud
      // providers routinely return null — which is why the hash, not the
      // mtime, is what W5 actually compares.
      val modified = idx(DocumentsContract.Document.COLUMN_LAST_MODIFIED)?.let { i ->
        if (it.isNull(i)) null else it.getLong(i)
      }
      val flags = idx(DocumentsContract.Document.COLUMN_FLAGS)?.let { i -> it.getInt(i) } ?: 0
      val supportsWrite =
          flags and DocumentsContract.Document.FLAG_SUPPORTS_WRITE != 0
      return Meta(name, size, modified, supportsWrite)
    }
  }

  /** What WE hold, as opposed to what the provider allows. Both must be true. */
  private fun holdsWrite(uri: Uri): Boolean {
    val held = resolver?.persistedUriPermissions?.firstOrNull { it.uri == uri }
    // No persisted row does not mean no access: the session grant from a pick
    // or an intent is not listed. Absent a row we trust the provider flag and
    // let the write itself be the final word.
    return held?.isWritePermission ?: true
  }

  // ── Probing (W3) ───────────────────────────────────────────────────────────

  private fun probe(uri: Uri): Map<String, Any?> {
    val meta = query(uri) ?: return mapOf("state" to "unreachable", "reason" to "fileGone")
    // Two facts, and both have to hold: what the provider allows
    // (COLUMN_FLAGS) and what we hold (the persisted grant). Either one alone
    // reports writable for a file the save would then fail on.
    if (!meta.providerWritable) {
      return mapOf("state" to "readOnly", "reason" to "providerNoWrite")
    }
    if (!holdsWrite(uri)) {
      return mapOf("state" to "readOnly", "reason" to "permissionReadOnly")
    }
    return mapOf("state" to "writable", "reason" to "")
  }

  // ── Writing ────────────────────────────────────────────────────────────────

  private fun save(
      uri: Uri,
      bytes: ByteArray?,
      expected: String,
      force: Boolean
  ): Map<String, Any?> {
    val resolver = this.resolver ?: return mapOf("outcome" to "lostAccess", "reason" to "grantRevoked")
    if (bytes == null) return mapOf("outcome" to "failed", "reason" to "noBytes")

    val current =
        try {
          resolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: SecurityException) {
          return mapOf("outcome" to "lostAccess", "reason" to "grantRevoked")
        } catch (e: Exception) {
          null
        }
            ?: return mapOf("outcome" to "lostAccess", "reason" to "fileGone")

    if (!force && sha256Hex(current) != expected) {
      return mapOf(
          "outcome" to "conflict", "sha256" to sha256Hex(current), "sizeBytes" to current.size)
    }

    // There is no atomic replace across a SAF URI (ADR-0030 §6). Before
    // truncating we keep the old bytes app-privately, so a crash between the
    // truncation and the last byte is recoverable instead of total.
    val recovery = writeRecoveryCopy(current)
    try {
      // "wt", NOT "w": plain "w" does not truncate on many providers, so a
      // shorter document leaves the tail of the old one behind — a byte
      // corruption that only shows up on real hardware.
      resolver.openOutputStream(uri, "wt")?.use { out ->
        out.write(bytes)
        out.flush()
      } ?: return mapOf("outcome" to "lostAccess", "reason" to "fileGone")
    } catch (e: SecurityException) {
      return mapOf("outcome" to "lostAccess", "reason" to "grantRevoked")
    } catch (e: Exception) {
      return mapOf("outcome" to "failed", "reason" to (e.message ?: "writeFailed"))
    } finally {
      // Only on the happy path does the recovery copy stop being needed.
      recovery?.delete()
    }

    return mapOf(
        "outcome" to "ok",
        "sha256" to sha256Hex(bytes),
        "sizeBytes" to bytes.size,
        "modifiedAtMs" to query(uri)?.modifiedAtMs)
  }

  private fun writeRecoveryCopy(bytes: ByteArray): File? {
    if (bytes.size > MAX_RECOVERY_BYTES) return null
    val context = activity?.applicationContext ?: return null
    return try {
      val dir = File(context.filesDir, "external_recovery").apply { mkdirs() }
      File(dir, "${sha256Hex(bytes)}.md").apply { writeBytes(bytes) }
    } catch (e: Exception) {
      null
    }
  }

  // ── Clipboard ──────────────────────────────────────────────────────────────

  private fun clipboardRead(): Map<String, Any?> {
    val context = activity?.applicationContext ?: return emptyMap()
    val manager =
        context.getSystemService(android.content.Context.CLIPBOARD_SERVICE)
            as? android.content.ClipboardManager
            ?: return emptyMap()
    val clip = manager.primaryClip ?: return emptyMap()
    if (clip.itemCount == 0) return emptyMap()
    val item = clip.getItemAt(0)
    val out = mutableMapOf<String, Any?>()
    item.htmlText?.let { out["html"] = it }
    item.uri?.let { uri ->
      val mime = resolver?.getType(uri)
      if (mime != null && mime.startsWith("image/")) {
        val bytes =
            try {
              resolver?.openInputStream(uri)?.use { it.readBytes() }
            } catch (e: Exception) {
              null
            }
        if (bytes != null) {
          out["imageBytes"] = bytes
          out["imageMime"] = mime
        }
      }
    }
    return out
  }

  private fun sha256Hex(bytes: ByteArray): String =
      MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
}
