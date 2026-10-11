import Foundation

// MD5 is required by the Subsonic token protocol, never used for credential storage.
public enum SubsonicToken {
    public static func hash(password: String, salt: String) -> String {
        md5(Array((password + salt).utf8))
    }

    static func md5(_ input: [UInt8]) -> String {
        let shifts: [UInt32] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
            5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
            4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
        ]
        let constants: [UInt32] = (1...64).map { UInt32(abs(sin(Double($0))) * 4294967296.0) }
        var bytes = input
        let length = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for i in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: length >> (i * 8))) }
        var state: [UInt32] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476]
        for start in stride(from: 0, to: bytes.count, by: 64) {
            let words: [UInt32] = (0..<16).map { i in
                let p = start + i * 4
                return UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3])
                    << 24
            }
            var a = state[0], b = state[1], c = state[2], d = state[3]
            for i in 0..<64 {
                let f: UInt32, g: Int
                switch i {
                case 0..<16:
                    f = (b & c) | (~b & d)
                    g = i
                case 16..<32:
                    f = (d & b) | (~d & c)
                    g = (5 * i + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 * i + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * i) % 16
                }
                let value = a &+ f &+ constants[i] &+ words[g]
                let rotated = (value << shifts[i]) | (value >> (32 - shifts[i]))
                a = d
                d = c
                c = b
                b = b &+ rotated
            }
            state[0] = state[0] &+ a
            state[1] = state[1] &+ b
            state[2] = state[2] &+ c
            state[3] = state[3] &+ d
        }
        return state.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) } }
            .map { String(format: "%02x", $0) }.joined()
    }
}
