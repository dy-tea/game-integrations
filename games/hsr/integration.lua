type Variant = {
    platform: string,
    edition: string
}

return {
    standard = 1,

    editions = function(platform: string)
        local hyvlib = import("hyvlib").hyvlib

        local editions = {}

        for name, edition in pairs(hyvlib.hsr) do
            table.insert(editions, {
                name = name,
                title = edition.title
            })
        end

        return editions
    end,

    game = {
        get_status = function(variant: Variant)
            local hyvlib = import("hyvlib").hyvlib

            if not hyvlib.hsr[variant.edition] then
                error(`invalid edition: {variant.edition}`)
            end

            local game = hyvlib.hsr[variant.edition]

            local latest = game.api.get().version
            local result, current = pcall(game.parse_version)

            if not result or not current then
                return "not-installed"
            end

            if latest > current then
                return "update-required"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            local iter = import("iterable")
            local hyvlib = import("hyvlib").hyvlib

            if not hyvlib.hsr[variant.edition] then
                error(`invalid edition: {variant.edition}`)
            end

            local game = hyvlib.hsr[variant.edition]

            local api = game.api.get()
            local result, current = pcall(game.parse_version)

            if not result or not current then
                return {
                    title = {
                        en = "Install game",
                        ru = "Установить игру"
                    },

                    description = {
                        en = "You don't have this game installed",
                        ru = "У вас не установлена эта игра"
                    },

                    pipeline = {
                        -- Download
                        {
                            title = {
                                en = "Download",
                                ru = "Скачать"
                            },

                            description = {
                                en = "Download archives with game files",
                                ru = "Скачать архивы с файлами игры"
                            },

                            perform = function(updater)
                                local temp_folder = path.temp_dir()

                                local expected_total = iter(clone(api.segments))
                                    .map(function(segment) return segment.download_size end)
                                    .sum()

                                local downloaded_total = 0

                                for _, segment in iter(clone(api.segments)) do
                                    local segment_name = path.file_name(segment.url)

                                    downloader.download(segment.url, {
                                        output_file = path.join(temp_folder, segment_name),
                                        continue_downloading = true,

                                        progress = function(current, total, diff)
                                            downloaded_total += diff

                                            updater({
                                                title = {
                                                    en = `Downloading {segment_name}`,
                                                    ru = `Скачивается {segment_name}`
                                                },

                                                progress = {
                                                    current = downloaded_total,
                                                    total = math.max(expected_total, downloaded_total),

                                                    format = function()
                                                        local current = downloaded_total / 1000 / 1000 / 1000
                                                        local total = math.max(expected_total, downloaded_total) / 1000 / 1000 / 1000

                                                        current = math.floor(current * 100) / 100
                                                        total = math.floor(total * 100) / 100

                                                        return {
                                                            en = `Downloaded {current} GB / {total} GB`,
                                                            ru = `Скачано {current} ГБ / {total} ГБ`
                                                        }
                                                    end
                                                }
                                            })
                                        end
                                    })
                                end
                            end
                        },

                        -- Extract
                        {
                            title = {
                                en = "Extract",
                                ru = "Распаковать"
                            },

                            description = {
                                en = "Extract game files from archives",
                                ru = "Распаковать файлы игры из архивов"
                            },

                            perform = function(updater)
                                local temp_folder = path.temp_dir()

                                local archives = iter(clone(api.segments))
                                    .map(function(segment)
                                        local segment_name = path.file_name(segment.url)
                                        local segment_path = path.join(temp_folder, segment_name)

                                        local handle = archive.open(segment_path)

                                        return {
                                            name   = segment_name,
                                            handle = handle
                                        }
                                    end)
                                    .collect()

                                local expected_total = iter(clone(archives))
                                    .map(function(info)
                                        return iter(archive.entries(info.handle))
                                            .map(function(entry) return entry.size end)
                                            .sum()
                                    end)
                                    .sum()

                                local downloaded_total = 0

                                for _, info in iter(archives) do
                                    archive.extract(info.handle, game.paths.base_folder, function(current, total, diff)
                                        downloaded_total += diff

                                        updater({
                                            title = {
                                                en = `Extracting {info.name}`,
                                                ru = `Распаковывается {info.name}`
                                            },

                                            progress = {
                                                current = downloaded_total,
                                                total = math.max(expected_total, downloaded_total),

                                                format = function()
                                                    local current = downloaded_total / 1000 / 1000 / 1000
                                                    local total = math.max(expected_total, downloaded_total) / 1000 / 1000 / 1000

                                                    current = math.floor(current * 100) / 100
                                                    total = math.floor(total * 100) / 100

                                                    return {
                                                        en = `Extracted {current} GB / {total} GB`,
                                                        ru = `Распаковано {current} ГБ / {total} ГБ`
                                                    }
                                                end
                                            }
                                        })
                                    end)

                                    archive.close(info.handle)
                                end
                            end
                        }
                    }
                }
            end

            -- TODO
            return nil
        end,

        get_launch_info = function(variant: Variant)
            return {
                status = "disabled",
                hint = {
                    en = "It's a test implementation not meant for real use",
                    ru = "Это тестовая реализация, не предназначенная для реального использования"
                },
                binary = ""
            }
        end
    },

    settings = {
        get_property = function(name: string)
            return nil
        end,

        set_property = function(name: string, value: any) end,

        get_layout = function(variant: Variant)
            return {}
        end
    }
}
