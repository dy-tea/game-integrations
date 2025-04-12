-- components/wine v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>
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

return function(imports)
    local wine_versions_cache = nil

    local function get_versions()
        if not wine_versions_cache then
            wine_versions_cache = {}

            local groups = {
                { name = "wine_staging_tkg", title = "Wine-Staging-TkG", src = imports.wine_staging_tkg }
            }

            for _, group in groups do
                table.insert(wine_versions_cache, {
                    name = group.name,
                    title = group.title,
                    versions = str.decode(str.from_bytes(group.src), "json")
                })
            end
        end

        return clone(wine_versions_cache)
    end

    return {
        get_versions = get_versions
    }
end
