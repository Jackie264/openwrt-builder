#!/usr/bin/env python3

import http.server
import socketserver
import os
import urllib.parse
import html
import sys
import mimetypes
import datetime
import time
from socketserver import ThreadingMixIn # 导入 ThreadingMixIn

# --- 配置 ---
# 脚本监听的本地端口
LISTEN_PORT = 8001
# 您的 feeds 所在的物理目录
FILE_SERVER_ROOT = "/home/ubuntu/Downloads/firmware"
# Caddy 服务 CSS 文件的 URL 路径 (相对于 :8080 站点的根)
CSS_URL = "/style/main.css"
# --- 结束配置 ---

# Helper function for human-readable file size
def human_readable_size(size_bytes):
    if size_bytes is None:
        return "-"
    if size_bytes == 0:
        return "0 B"
    size_name = ("B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB")
    i = 0
    while i < len(size_name) - 1 and size_bytes >= 1024:
        size_bytes /= 1024
        i += 1
    format_string = "{:.0f} {}" if i == 0 else "{:.1f} {}"
    return format_string.format(size_bytes, size_name[i])

# Helper function for date formatting like "Tue Apr 18 04:48:32 2017"
def format_mtime(timestamp):
    if timestamp is None:
        return "-"
    try:
        # The format code for "Weekday Mon Day HH:MM:SS YYYY" is "%a %b %d %H:%M:%S %Y"
        return datetime.datetime.fromtimestamp(timestamp).strftime("%a %b %d %H:%M:%S %Y")
    except (ValueError, TypeError):
        return "-" # Handle potential errors in timestamp

class CustomListingAndFileHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # 1. 解析并解码请求的 URL 路径
        parsed_url = urllib.parse.urlparse(self.path)
        url_path = parsed_url.path
        try:
            # Decode URL path, handle potential errors
            decoded_url_path = urllib.parse.unquote(url_path, errors='surrogateescape')
            # Normalize path components
            decoded_url_path = os.path.normpath(decoded_url_path)
        except Exception:
            self.send_error(http.HTTPStatus.BAD_REQUEST, "Bad path.")
            return

        # 2. 将 URL 路径映射到服务器的物理文件路径
        try:
            abs_root = os.path.abspath(FILE_SERVER_ROOT)
            # Join root with the requested path, ensuring security against traversal
            # lstrip('/') is important if joining with absolute root
            physical_path = os.path.normpath(os.path.join(abs_root, decoded_url_path.lstrip('/')))
        except Exception:
             self.send_error(http.HTTPStatus.INTERNAL_SERVER_ERROR, "Error processing path.")
             return

        # 3. 安全检查：确保最终路径在允许的根目录内
        # Use os.path.commonpath to check if physical_path starts with abs_root safely
        if not os.path.commonpath([abs_root, physical_path]) == abs_root:
             self.send_error(http.HTTPStatus.FORBIDDEN, "Access denied.")
             return
        # Also handle the specific case where the requested path might point outside via symlink
        # A more robust check might involve os.path.realpath, but it can be slow
        # For simplicity, relying on os.path.normpath and commonpath for basic traversal prevention


        # --- 判断路径类型并处理 ---

        try:
            if os.path.isdir(physical_path):
                # 如果是目录，生成并返回目录列表 HTML
                self.serve_directory_listing(physical_path, decoded_url_path)
            elif os.path.isfile(physical_path):
                # 如果是文件，读取文件内容并返回
                self.serve_file(physical_path)
            elif os.path.exists(physical_path):
                 # 如果存在但不是目录也不是文件 (例如符号链接到不存在的目标，特殊文件等)
                 self.send_error(http.HTTPStatus.NOT_FOUND, "Resource type not supported.")
            else:
                # 如果路径不存在
                self.send_error(http.HTTPStatus.NOT_FOUND, "Resource not found.")
        except PermissionError:
             # Handle permission errors during isdir/isfile/exists check
             self.send_error(http.HTTPStatus.FORBIDDEN, "Permission denied.")
        except Exception as e:
             # Catch any other unexpected errors during path checking
             print(f"Unexpected error processing path {physical_path}: {e}", file=sys.stderr)
             self.send_error(http.HTTPStatus.INTERNAL_SERVER_ERROR, "Internal server error.")


    def serve_directory_listing(self, physical_path, display_url_path):
        """生成并提供目录列表 HTML (使用表格布局)"""
        try:
            items = os.listdir(physical_path)

            # --- 添加过滤逻辑 ---
            # 过滤掉以 '.' 开头的文件和文件夹，但保留 '.' 和 '..' 如果它们出现在原始列表中（尽管os.listdir通常不包含它们）
            # 更安全的做法是过滤掉所有以点开头的，除了我们单独处理的 '..' 父目录链接
            filtered_items = [
                name for name in items
                if not name.startswith('.') # 过滤掉以点开头的文件名
            ]
            # --- 过滤逻辑结束 ---

            # 对过滤后的列表进行排序
            filtered_items.sort(key=str.lower)

        except OSError:
            print(f"Error listing directory {physical_path}: {e}", file=sys.stderr)
            self.send_error(
                http.HTTPStatus.INTERNAL_SERVER_ERROR,
                "Could not list directory: Permission denied or directory not found."
            )
            return

        r = []
        r.append('<!DOCTYPE HTML>')
        r.append('<html><head>')
        r.append('<meta charset="utf-8">')
        r.append(f'<title>Index of {html.escape(display_url_path)}</title>')
        r.append(f'<link rel="stylesheet" href="{html.escape(CSS_URL)}">')
        r.append('</head><body>')

        # --- Add container div ---
        r.append('<div class="container">')

                # --- 生成面包屑标题 ---
        header_components = ['<h1>Index of ']

        # 总是添加根目录 '/' 的链接
        header_components.append('<a href="/">/</a>')

        # 如果不是根目录，处理路径段
        if display_url_path != '/':
            # 分割路径为段，去除开头和结尾的斜杠
            segments = display_url_path.strip('/').split('/')

            # 用于构建 URL 链接的累加器，从根目录开始
            current_url_accumulator = '/'

            for i, segment in enumerate(segments):
                # --- 决定分隔符是空格还是 " / " ---
                # 如果是第一个路径段 (i == 0)，分隔符是空格 ' '
                # 如果是后续路径段 (i > 0)，分隔符是 " / "
                separator = ' ' if i == 0 else ' / '

                # 添加分隔符
                header_components.append(separator)

                # HTML 转义当前路径段的显示名称
                escaped_segment = html.escape(segment)

                # 添加分隔符：只在处理第二个及后续段时添加分隔符***
                #if i > 0: # 如果这不是第一个路径段 (i > 0)
                #   header_parts.append(' / ') # 则在它前面添加分隔符

                # 构建当前路径段对应的 URL
                # 使用 urllib.parse.quote 处理 URL 中的特殊字符
                quoted_segment_for_url = urllib.parse.quote(segment, errors='surrogateescape')
                # 使用 urljoin 安全地构建下一级路径，并确保是目录链接（以 '/' 结尾）
                current_url_accumulator = urllib.parse.urljoin(current_url_accumulator, quoted_segment_for_url + '/')


                if i < len(segments) - 1:
                    # 如果不是最后一个路径段，生成一个链接
                    # 链接 href 是到当前段的路径 (例如 /mx5300/latest/)
                    header_components.append(f'<a href="{current_url_accumulator}">{escaped_segment}</a>')
                else:
                    # 如果是最后一个路径段，只显示文本，不加链接
                    # 文本不包含结尾的斜杠，以匹配官网样式
                    header_components.append(f'{escaped_segment}')


        header_components.append('</h1>')
        # --- 面包屑标题生成结束 ---

        r.append(''.join(header_components)) # 将所有部分合并为完整的标题 HTML 并添加到列表

        r.append('<hr>')

        # --- Table structure ---
        r.append('<table>')
        r.append('<thead>')
        r.append('<tr>')
        r.append('<th>File Name</th>')
        r.append('<th>File Size</th>')
        r.append('<th>Date</th>')
        r.append('</tr>')
        r.append('</thead>')
        r.append('<tbody>')

        # Add "Parent Directory" row
        if display_url_path != '/':
            parent_url_path = os.path.normpath(os.path.join(display_url_path, os.pardir))
            parent_url_path = parent_url_path if parent_url_path.endswith('/') else parent_url_path + '/'
            quoted_parent_url_path = urllib.parse.quote(parent_url_path, errors='surrogateescape') # Encode URL path
            r.append('<tr>')
            r.append(f'<td><a href="{quoted_parent_url_path}">../</a></td>')
            r.append('<td>-</td>') # Size column for parent dir
            r.append('<td>-</td>') # Date column for parent dir
            r.append('</tr>')

        # List items
        for name in filtered_items:
            item_physical_path = os.path.join(physical_path, name)

            # Construct URL path for the item
            base_url_for_join = display_url_path if display_url_path.endswith('/') else display_url_path + '/'
            # Encode item name for URL
            quoted_item_name = urllib.parse.quote(name, errors='surrogateescape')
            item_url_path = urllib.parse.urljoin(base_url_for_join, quoted_item_name)


            displayname = html.escape(name)
            is_dir = os.path.isdir(item_physical_path)
            if is_dir:
                displayname += "/"
                # Ensure directory links end with a slash in the URL
                if not item_url_path.endswith('/'):
                     item_url_path += '/'

            # Get stats
            stats = None
            try:
                stats = os.stat(item_physical_path)
            except OSError:
                # Handle cases where file/dir might disappear or have permission issues after listing but before stat
                pass # stats remains None

            # Prepare display values
            size_display = "-"
            date_display = "-" # Default to "-" for date as well if stats fail

            if stats:
                 if not is_dir: # Only get size for files
                    size_display = human_readable_size(stats.st_size)
                 # Get and format date for both files and directories (last modified)
                 date_display = format_mtime(stats.st_mtime)


            r.append('<tr>')
            r.append(f'<td><a href="{item_url_path}">{displayname}</a></td>')
            r.append(f'<td>{size_display}</td>')
            r.append(f'<td>{date_display}</td>')
            r.append('</tr>')

        r.append('</tbody>')
        r.append('</table>')
        # --- End Table structure ---


        r.append('<hr>')

        # --- Endding container div ---
        r.append('</div>')

        # You can add footer here if needed
        r.append('</body></html>')

        encoded_html = '\n'.join(r).encode('utf-8')

        self.send_response(http.HTTPStatus.OK)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded_html)))
        self.end_headers()
        self.wfile.write(encoded_html)


    def serve_file(self, physical_path):
        """读取并提供文件内容"""
        try:
            # Try to guess Content-Type
            mimetype, _ = mimetypes.guess_type(physical_path)
            if mimetype is None:
                mimetype = 'application/octet-stream' # Default type

            file_size = os.path.getsize(physical_path)

            self.send_response(http.HTTPStatus.OK)
            self.send_header("Content-type", mimetype)
            self.send_header("Content-Length", str(file_size))
            self.end_headers()

            # Open and stream the file content
            with open(physical_path, 'rb') as f:
                # Use copyfileobj for efficient streaming
                import shutil
                shutil.copyfileobj(f, self.wfile)

        except FileNotFoundError:
            # This should ideally not happen if os.path.isfile passed, but for robustness
             self.send_error(http.HTTPStatus.NOT_FOUND, "File not found or inaccessible.")
        except PermissionError:
             self.send_error(http.HTTPStatus.FORBIDDEN, "Permission denied to read file.")
        except Exception as e:
            # Handle other possible errors during file serving
            print(f"Error serving file {physical_path}: {e}", file=sys.stderr)
            self.send_error(http.HTTPStatus.INTERNAL_SERVER_ERROR, "Error reading file.")


# Use ThreadingTCPServer to handle multiple requests concurrently
class ThreadedTCPServer(ThreadingMixIn, socketserver.TCPServer):
    pass


# --- 运行服务器 ---
if __name__ == "__main__":
    # 确保 FILE_SERVER_ROOT 存在且可读
    if not os.path.isdir(FILE_SERVER_ROOT):
        print(f"Error: Feeds root directory not found or not accessible: {FILE_SERVER_ROOT}", file=sys.stderr)
        sys.exit(1)

    server_address = ('', LISTEN_PORT)
    try:
        with ThreadedTCPServer(server_address, CustomListingAndFileHandler) as httpd:
            print(f"Starting custom listing and file server on port {LISTEN_PORT}")
            print(f"Serving content from: {FILE_SERVER_ROOT}")
            # Keep the server running indefinitely
            httpd.serve_forever()
    except PermissionError:
        print(f"Error: Permission denied to bind on port {LISTEN_PORT}. Try running with sudo or a higher port.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        sys.exit(1)
