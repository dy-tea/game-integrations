-- Direct download links are taken from here: https://archive.org/details/votv-archive
-- Pre-Alpha 0.8.2: https://archive.org/download/votv-archive/pa0082_0012.7z

type Variant = {
    platform: string,
    edition: string
}

return {
    standard = 1,

    editions = function(platform: string)
        return {
            name = "default",
            title = {
                en = "Default",
                ru = "Стандартная"
            }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            return "installed"
        end,

        get_diff = function(variant: Variant)
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
