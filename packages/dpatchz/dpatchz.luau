-- dpatchz v0.0.0
-- Copyright (C) 2025  Dylan Donnell <dylan.donnell@student.griffith.ie>
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

--!nocheck

local data_dir_path: string = path.persist_dir("dpatchz")
local exe_path: string = path.join(data_dir_path, "dpatchz")
local version_file_path: string = path.join(data_dir_path, "version")

-- get latest json from github api
local function latest_json()
    local resp = net.fetch("https://api.github.com/repos/dawn-winery/dpatchz/releases/latest", {
        method = "get",
        headers = {
            ["User-Agent"] = "curl/7.88.1",
            ["Accept"] = "application/vnd.github.v3+json"
        },
        body = {}
    })

    if not resp then
        error(`github api is not accessible`)
    end

    -- decode response json
    if resp.is_ok then
        return str.decode(str.from_bytes(resp.body), "json")
    end

    return nil
end

-- get latest version
local function latest_version()
    local json = latest_json()
    return json.tag_name
end

-- get installed version
local function installed_version()
    if fs.exists(version_file_path) then
        return str.from_bytes(fs.read_file(version_file_path))
    end

    return nil
end

-- download dpatch executable from version
local function fetch(version: string)
    -- remove old executable if present
    if fs.exists(exe_path) then
        fs.remove(exe_path)
    end

    -- download latest release
    local handle = downloader.create()
    local download = downloader.download(handle, {
        url = "https://github.com/dawn-winery/dpatchz/releases/download/" .. version .. "/dpatchz",
        output_file = exe_path,
        on_finish = function(total)
            print(`dpatchz - downloaded {total / 1024} KiB`)
        end
    })
    downloader.wait(download)
    downloader.close(handle)

    -- write version to version file
    if fs.exists(version_file_path) then
        fs.remove(version_file_path)
    end
    fs.write_file(version_file_path, version)

    -- give executable permissions
    local output = process.exec("chmod", {"+x", exe_path})
    if not output.is_ok then
        local stdout = str.from_bytes(output.stdout)
        local stderr = str.from_bytes(output.stderr)
        error(`exited with status code {output.status}    stdout: {stdout}    stderr: {stderr}`)
    end
end

-- get the hash of the dpatchz executable and check
local function check_validity()
    local json = latest_json()

    if not fs.exists(exe_path) then
        error(`dpatchz executable not found at {exe_path}`)
    end

    -- get sha256 digest from asset metadata
    local digest = nil
    for _, asset in json.assets do
        if asset.name == "dpatchz" then
            -- remove sha256 prefix
            digest = asset.digest:gsub("sha256:", "")
            break
        end
    end
    if not digest then
        error(`could not find digest for dpatchz executable`)
    end

    -- calculate the file's hash
    local file_hash = hash.file(exe_path, "sha2-256")
    local hashed = ""
    for _, char in file_hash do
        hashed ..= string.format("%02x", char)
    end
    hashed = string.lower(hashed)

    -- compare hashes, remove executable if offending
    if digest ~= hashed then
        fs.remove(exe_path)
        fs.remove(version_file_path)
        error(`file hash does not match digest, removing`)
    end
end

local function init()
    local ver = installed_version()
    local latest = latest_version()

    -- need version to exist
    if not ver and not latest then
        error("Failed to fetch latest version")
        return
    end

    -- update or install
    if latest and (not ver or ver ~= latest) then
        fetch(latest)
    end
end

return {
    init = init,
    patch_file = function(diff_file: string, old_path: string, new_path: string?)
        -- check for process api presence
        if not process then
            error(`dpatchz module must have access to the v1 process API`)
        end

        -- download or update executable
        init()

        -- check paths
        if not (path.accessible(exe_path) or path.accessible(old_path) or (new_path and path.accessible(new_path))) then
            error(`one or more paths are not accessible, check if these exist: exe_path: {exe_path}    old_path: {old_path}    new_path: {new_path}`)
        end

        -- ensure dpatchz executable is valid
        check_validity()

        -- run patcher
        local output = nil
        if new_path then
            output = process.exec("bash", {"-c", `exec {exe_path} {diff_file} {old_path} {new_path}`})
        else
            output = process.exec("bash", {"-c", `exec {exe_path} -i {diff_file} {old_path}`})
        end

        -- output errors
        if not output.is_ok then
            local stdout = str.from_bytes(output.stdout)
            local stderr = str.from_bytes(output.stderr)
            error(`exited with status code {output.status}    stdout: {stdout}    stderr: {stderr}`)
        end
    end
}
