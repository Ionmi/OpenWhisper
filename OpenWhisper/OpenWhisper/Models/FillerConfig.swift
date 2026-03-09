import Foundation

struct FillerConfig: Codable {
    var fillersByLanguage: [String: [String]]

    static let `default` = FillerConfig(fillersByLanguage: [
        "es": ["eh", "um", "ah", "mmm"],
        "en": ["um", "uh", "uh huh", "hmm"],
        "fr": ["euh", "ben", "genre", "en fait", "du coup", "bah", "voila"],
        "de": ["ah", "ahm", "also", "halt", "sozusagen", "quasi", "na ja"],
        "it": ["eh", "ciao", "allora", "praticamente", "cioe", "insomma"],
        "pt": ["eh", "tipo", "ne", "entao", "basicamente", "quer dizer"],
        "ja": ["えーと", "あの", "その", "まあ", "なんか"],
        "ko": ["음", "어", "그", "뭐", "아"],
        "zh": ["嗯", "那个", "就是", "然后", "这个"],
        "ru": ["эм", "ну", "вот", "типа", "как бы", "значит"],
        "ar": ["يعني", "هم", "اه"],
        "hi": ["उम", "अच्छा", "तो", "मतलब"],
    ])
}
