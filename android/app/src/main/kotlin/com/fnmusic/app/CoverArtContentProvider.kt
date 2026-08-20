package com.fnmusic.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * 仅向外部媒体客户端公开生成的封面缓存。
 *
 * Android Auto/AAOS 与应用不在同一进程，不能读取 app-private 的 file://
 * 路径。Provider 只接受 SHA-1 命名的缓存文件，避免暴露应用其余文件。
 *
 * authority 固定为 `com.fnmusic.app.coverart`（见 AndroidManifest provider
 * 声明，与 Dart 侧 [ApiClient.kApplicationId] 保持一致）。
 */
class CoverArtContentProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String {
        fileForUri(uri)
        return "image/*"
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = fileForUri(uri)
        val columns = projection?.map { it }?.toTypedArray()
            ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val values: Array<Any?> = columns.map { column ->
            when (column) {
                OpenableColumns.DISPLAY_NAME -> file.name
                OpenableColumns.SIZE -> file.length()
                else -> null
            }
        }.toTypedArray()
        return MatrixCursor(columns).apply { addRow(values) }
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Album art is read-only")
        return ParcelFileDescriptor.open(fileForUri(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Album art is read-only")
        val file = fileForUri(uri)
        val descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(descriptor, 0, file.length())
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? {
        throw UnsupportedOperationException("Album art is read-only")
    }

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int {
        throw UnsupportedOperationException("Album art is read-only")
    }

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int {
        throw UnsupportedOperationException("Album art is read-only")
    }

    private fun fileForUri(uri: Uri): File {
        val name = uri.lastPathSegment ?: throw FileNotFoundException("Missing album art name")
        if (!FILE_NAME.matches(name)) throw FileNotFoundException("Invalid album art name")

        val appContext = context ?: throw FileNotFoundException("Provider is not ready")
        val root = File(appContext.cacheDir, COVER_DIRECTORY).canonicalFile
        val target = File(root, name).canonicalFile
        if (!target.path.startsWith(root.path + File.separator) || !target.isFile) {
            throw FileNotFoundException("Album art not found")
        }
        return target
    }

    private companion object {
        const val COVER_DIRECTORY = "covers_v2"
        val FILE_NAME = Regex("^[0-9a-f]{40}\\.img$")
    }
}
