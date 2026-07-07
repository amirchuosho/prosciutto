import XCTest
import Compression
@testable import ProsciuttoKit

/// Verifies the Paste pasteboard-envelope decoder handles every serialization Paste uses:
/// bplist and JSON, each optionally compressed (LZFSE frame or raw DEFLATE). Uses
/// synthesized envelopes so it needs no real Paste store.
final class PasteEnvelopeTests: XCTestCase {
    private let uti = "public.utf8-plain-text"
    private let text = "hello, מזרח 🍖"

    private func jsonEnvelope() -> Data {
        let b64 = Data(text.utf8).base64EncodedString()
        let json = "[{\"types\":[\"\(uti)\"],\"dataByType\":{\"\(uti)\":\"\(b64)\"}}]"
        return Data(json.utf8)
    }

    private func bplistEnvelope() throws -> Data {
        let obj: [[String: Any]] = [["types": [uti], "dataByType": [uti: Data(text.utf8)]]]
        return try PropertyListSerialization.data(fromPropertyList: obj, format: .binary, options: 0)
    }

    private func compress(_ src: Data, _ algorithm: compression_algorithm) -> Data {
        let cap = src.count + 4096
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap); defer { dst.deallocate() }
        let n = src.withUnsafeBytes { raw in
            compression_encode_buffer(dst, cap, raw.bindMemory(to: UInt8.self).baseAddress!, src.count, nil, algorithm)
        }
        return Data(bytes: dst, count: n)
    }

    private func assertRecovers(_ data: Data, _ label: String) {
        let dbt = PasteReader.parseEnvelope(data)
        XCTAssertEqual(String(data: dbt[uti] ?? Data(), encoding: .utf8), text, "failed: \(label)")
    }

    func testBplist() throws { assertRecovers(try bplistEnvelope(), "bplist") }
    func testJSON() { assertRecovers(jsonEnvelope(), "json") }
    func testDeflatedJSON() { assertRecovers(compress(jsonEnvelope(), COMPRESSION_ZLIB), "deflate(json)") }
    func testLZFSEBplist() throws { assertRecovers(compress(try bplistEnvelope(), COMPRESSION_LZFSE), "lzfse(bplist)") }
    func testDeflatedBplist() throws { assertRecovers(compress(try bplistEnvelope(), COMPRESSION_ZLIB), "deflate(bplist)") }

    func testGarbageIsEmpty() {
        XCTAssertTrue(PasteReader.parseEnvelope(Data([0x00, 0x01, 0x02, 0x03])).isEmpty)
    }
}
