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
local version_file_path: string = path.join(data_dir_path, ".version")

-- get latest version from github api
local function latest_version()
    local resp = net.fetch("https://api.github.com/repos/dawn-winery/dpatchz/releases/latest", {
        method = "get",
        headers = {
            ["User-Agent"] = "curl/7.88.1",
            ["Accept"] = "application/vnd.github.v3+json"
        },
        body = {}
    })

    -- fetch version from github api
    if resp.is_ok then
        local json = str.decode(str.from_bytes(resp.body), "json")
        return json.tag_name
    end

    return nil
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
    local resp = net.fetch("https://github.com/dawn-winery/dpatchz/releases/download/" .. version .. "/dpatchz")

    if not resp.is_ok then
        error("Failed to fetch dpatch executable")
        return
    end

    -- write executable
    if fs.exists(exe_path) then
        fs.remove(exe_path)
    end
    fs.write_file(exe_path, resp.body)

    -- write version to .version
    if fs.exists(version_file_path) then
        fs.remove(version_file_path)
    end
    fs.write_file(version_file_path, version)
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
        if not fs.exists(exe_path) then
            init()
            local output = process.exec("chmod", {"+x", exe_path})
            if not output.is_ok then
                local stdout = str.from_bytes(output.stdout)
                local stderr = str.from_bytes(output.stderr)
                error(`exited with status code {output.status}    stdout: {stdout}    stderr: {stderr}`)
            end
        end

        local output = nil
        if new_path then
            output = process.exec("bash", {"-c", `exec {exe_path} {diff_file} {old_path} {new_path}`})
        else
            output = process.exec("bash", {"-c", `exec {exe_path} -i {diff_file} {old_path}`})
        end

        if not output.is_ok then
            local stdout = str.from_bytes(output.stdout)
            local stderr = str.from_bytes(output.stderr)
            error(`exited with status code {output.status}    stdout: {stdout}    stderr: {stderr}`)
        end
    end
}
