import Foundation

struct FillerConfig: Codable {
    var fillersByLanguage: [String: [String]]

    static let `default` = FillerConfig(fillersByLanguage: [
        "es": ["eh", "um", "ah", "mmm"],
        "en": ["um", "uh", "uh huh", "hmm"],
        "fr": ["euh", "bah", "hmm"],
        "de": ["ah", "ahm", "hmm"],
        "it": ["eh", "uhm", "mmm"],
        "pt": ["eh", "hm", "mmm"],
        "ja": ["えーと", "あの"],
        "ko": ["음", "어"],
        "zh": ["嗯", "那个"],
        "ru": ["эм", "хм"],
        "ar": ["هم", "اه"],
        "hi": ["उम", "हम्म"],
    ])
}
