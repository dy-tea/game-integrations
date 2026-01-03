-- protobuf v0.1.2
-- Copyright (C) 2025 - 2026  Nikita Podvirnyi <krypt0nn@vk.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

type EncodeOptions = {
    -- Path to the protobuf file.
    protobuf: string,

    -- Path to a folder where protobuf file is stored. If not specified - then
    -- parsed automatically from the protobuf path.
    proto_path: string | nil,

    -- Message type to encode.
    type: string,

    -- Input message content or path to input message file.
    input: string | { number }
}

type DecodeOptions = EncodeOptions

local download_info = {
    ["x86_64-linux"]   = { url = "https://github.com/protocolbuffers/protobuf/releases/download/v33.2/protoc-33.2-linux-x86_64.zip",   zip_hash = "dsvwaxssy4bek", bin_hash = "3kvwacoujjwx2" },
    ["aarch64-linux"]  = { url = "https://github.com/protocolbuffers/protobuf/releases/download/v33.2/protoc-33.2-linux-aarch_64.zip", zip_hash = "j7zeilhyn4wug", bin_hash = "mqrmiypc42n6q" },
    ["x86_64-darwin"]  = { url = "https://github.com/protocolbuffers/protobuf/releases/download/v33.2/protoc-33.2-osx-x86_64.zip",     zip_hash = "rpymqeceblrr6", bin_hash = "7iuxo2c7t4dzy" },
    ["aarch64-darwin"] = { url = "https://github.com/protocolbuffers/protobuf/releases/download/v33.2/protoc-33.2-osx-aarch_64.zip",   zip_hash = "e6nonogwb3bda", bin_hash = "o7vw7ockwggpa" }
}

local data_folder: string = path.persist_dir("protobuf")
local binary_path: string = path.join(data_folder, "protoc")

if not process then
    error("protobuf library requires process API support")
end

local function calc_file_hash(path: string): string
    local file_hash = hash.digitize_file("seahash", path):await()

    return str.encode(file_hash, "base32/nopad")
end

local function check_read_permissions(fs_path: string): boolean
    return path.permissions(fs_path).read
end

local function is_installed(platform: string)
    if not fs.exists(binary_path) then
        return false
    end

    if not download_info[platform] then
        error(`Platform '{platform}' is not supported by the protobuf library`)
    end

    return calc_file_hash(binary_path) == download_info[platform].bin_hash
end

return {
    -- Check if provided platform is supported by the library.
    is_supported = function(platform: string): boolean
        return download_info[platform] ~= nil
    end,

    -- Check if a protobuf binary for probided platform is installed.
    is_installed = is_installed,

    -- Install protobuf for provided platform.
    install = function(platform: string, updater: ((number, number) -> ()) | nil)
        if is_installed(platform) then
            return
        end

        if not download_info[platform] then
            error(`Platform '{platform}' is not supported by the protobuf library`)
        end

        local temp_archive_path = path.join(path.temp_dir(), `{platform}-protobuf.zip`)
        local temp_archive_extract_path = path.join(path.temp_dir(), `{platform}-protobuf`)
        local archive_binary_path = path.join(temp_archive_extract_path, "bin", "protoc")

        local handle = downloader.create()

        local task = downloader.download(handle, {
            url = download_info[platform].url,
            output_file = temp_archive_path,
            continue_download = false,

            on_update = function(current: number, total: number)
                if updater then
                    updater(current, total)
                end
            end
        })

        downloader.wait(task)
        downloader.close(handle)

        if calc_file_hash(temp_archive_path) ~= download_info[platform].zip_hash then
            error("hash mismatch on downloaded protoc archive")
        end

        handle = archive.open(temp_archive_path)

        archive.extract(handle, temp_archive_extract_path)
        archive.close(handle)

        if calc_file_hash(archive_binary_path) ~= download_info[platform].bin_hash then
            error("hash mismatch on extracted protoc binary")
        end

        if fs.exists(binary_path) then
            fs.remove_file(binary_path):await()
        end

        fs.move(archive_binary_path, binary_path):await()

        fs.remove_file(temp_archive_path):await()
        fs.remove_dir(temp_archive_extract_path):await()
    end,

    -- Encode protobuf message.
    encode = function(platform: string, options: EncodeOptions): { number }
        if not options.protobuf then
            error("protobuf path is not provided")
        end

        if not options.type then
            error("protobuf encode type is not provided")
        end

        if not options.input then
            error("protobuf encode input is not provided")
        end

        local proto_path = options.proto_path or path.parent(options.protobuf)

        if not check_read_permissions(options.protobuf) then
            error(`protobuf library doesn't have permissions to read '{options.protobuf}'`)
        end

        if not check_read_permissions(proto_path) then
            error(`protobuf library doesn't have permissions to read '{proto_path}'`)
        end

        local input = {}

        if typeof(options.input) == "string" then
            if fs.exists(options.input) then
                input = fs.read_file(options.input):await()
            else
                input = str.to_bytes(input)
            end
        else
            input = options.input :: { number }
        end

        local handle = process.open(binary_path, {
            "--proto_path", proto_path,
            "--encode", options.type,
            options.protobuf
        })

        process.stdin(handle, input)

        local output = process.wait(handle)

        if not output.is_ok then
            error(`failed to execute protoc binary: {str.from_bytes(output.stderr)}`)
        end

        return output.stdout
    end,

    -- Decode protobuf message.
    decode = function(platform: string, options: DecodeOptions): { number }
        if not options.protobuf then
            error("protobuf path is not provided")
        end

        if not options.type then
            error("protobuf decode type is not provided")
        end

        if not options.input then
            error("protobuf decode input is not provided")
        end

        local proto_path = options.proto_path or path.parent(options.protobuf)

        if not check_read_permissions(options.protobuf) then
            error(`protobuf library doesn't have permissions to read '{options.protobuf}'`)
        end

        if not check_read_permissions(proto_path) then
            error(`protobuf library doesn't have permissions to read '{proto_path}'`)
        end

        local input = {}

        if typeof(options.input) == "string" then
            if fs.exists(options.input) then
                input = fs.read_file(options.input):await()
            else
                input = str.to_bytes(input)
            end
        else
            input = options.input :: { number }
        end

        local handle = process.open(binary_path, {
            "--proto_path", proto_path,
            "--decode", options.type,
            options.protobuf
        })

        process.stdin(handle, input)

        local output = process.wait(handle)

        if not output.is_ok then
            error(`failed to execute protoc binary: {str.from_bytes(output.stderr)}`)
        end

        return str.from_bytes(output.stdout)
    end
}
