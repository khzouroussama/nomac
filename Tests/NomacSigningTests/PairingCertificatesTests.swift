import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// The certificates of a pairing, against libimobiledevice's `userpref.c`, pymobiledevice3's `ca.py`
/// and OpenSSL's reading of the same key.
@Suite struct PairingCertificatesTests {
    /// `openssl rsa -RSAPublicKey_out` of the test identity's key.
    static let pkcs1 = """
    -----BEGIN RSA PUBLIC KEY-----
    MIIBCgKCAQEAp7U0GOBUHch4sM0E8TTnWtlB7ISN20Fo9y8QceVhyiNCeC0/cXgo
    ZkerR/Z+k9hdPJxKnEiBtWyYJ63Xbobe8OzKX9zSQu0/op/YNUqVh1uo0j8bBVxk
    ZMwh3/v4ZxadtOvez8VqBfnX6SoPyG56jqRLjVn18gmE3IsKHwDct7zivWwKWvYC
    se9M4vjFX9rnvB2nlqGV3oINi0BPUsP35uMisbGfdzfyjE8ZPdBPqnQvGEmNlDaF
    j3Shj7AiAqdU4JHcK4yMdqu7Lvg4PrXsDcC+9z+hKs8Ik5yR6oSoFcMJiQq9iK5j
    eeJMVyFwcP1Dvn6vaiBgTX9O+Q+SZnSm7QIDAQAB
    -----END RSA PUBLIC KEY-----

    """
    /// The test identity's certificate's key, as a `SubjectPublicKeyInfo`.
    static let info = try! X509Certificate(der: SigningMaterialTests.certificates[0], path: "leaf").subjectPublicKeyInfo
    static let date = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!

    static func der(_ pem: [UInt8]) -> [UInt8] { PEM.blocks(in: String(decoding: pem, as: UTF8.self)).first!.der }

    /// The parts of a certificate: to-be-signed bytes, its fields, and the signature.
    static func parts(_ pem: [UInt8]) throws -> (tbs: [UInt8], fields: [DERReader.Element], signature: [UInt8]) {
        let outer = try #require(DERReader.elements(der(pem)).first)
        let elements = DERReader.elements(outer.content)
        return (elements[0].encoded, DERReader.elements(elements[0].content), Array(elements[2].content.dropFirst()))
    }

    @Test func thePublicKeyFormsAreOne() throws {
        #expect(try PairingCertificates.subjectPublicKeyInfo(Array(Self.pkcs1.utf8)) == Self.info)
        #expect(try PairingCertificates.subjectPublicKeyInfo(Array(PEM.text(label: "PUBLIC KEY", der: Self.info).utf8)) == Self.info)
        #expect(throws: NomacError.self) { try PairingCertificates.subjectPublicKeyInfo(Array("no key".utf8)) }
    }

    @Test func theRootSignsAllThree() throws {
        let chain = try PairingCertificates(devicePublicKey: Array(Self.pkcs1.utf8), at: Self.date)
        let root = try X509Certificate(der: Self.der(chain.rootCertificate), path: "root")
        for certificate in [chain.rootCertificate, chain.hostCertificate, chain.deviceCertificate] {
            let parts = try Self.parts(certificate)
            #expect(ProfileSignature.verifies(parts.signature, of: parts.tbs, digestAlgorithm: ProfileSignature.sha256, key: root.subjectPublicKeyInfo))
        }
    }

    @Test func theFieldsAreThoseOfAPairing() throws {
        let chain = try PairingCertificates(devicePublicKey: Array(Self.pkcs1.utf8), at: Self.date)
        let expectedValidity = DER.element(0x30, DER.element(0x17, Array("261106115900Z".utf8)) + DER.element(0x17, Array("361103120000Z".utf8)))
        for certificate in [chain.rootCertificate, chain.hostCertificate, chain.deviceCertificate] {
            let fields = try Self.parts(certificate).fields
            #expect(fields[0].encoded == [0xa0, 0x03, 0x02, 0x01, 0x02])
            #expect(fields[1].encoded == [0x02, 0x01, 0x01])
            #expect(fields[2].encoded == X509Builder.sha256WithRSA)
            #expect(fields[3].encoded == [0x30, 0x00])
            #expect(fields[4].encoded == expectedValidity)
            #expect(fields[5].encoded == [0x30, 0x00])
        }
        let keyUsage: [UInt8] = [0x30, 0x0e, 0x06, 0x03, 0x55, 0x1d, 0x0f, 0x01, 0x01, 0xff, 0x04, 0x04, 0x03, 0x02, 0x05, 0xa0]
        let notAuthority: [UInt8] = [0x30, 0x0c, 0x06, 0x03, 0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x02, 0x30, 0x00]
        func extensions(_ pem: [UInt8]) throws -> [[UInt8]] {
            let wrapper = try #require(try Self.parts(pem).fields.first { $0.tag == 0xa3 })
            return DERReader.elements(DERReader.elements(wrapper.content)[0].content).map(\.encoded)
        }
        #expect(try extensions(chain.rootCertificate) == [[0x30, 0x0f, 0x06, 0x03, 0x55, 0x1d, 0x13, 0x01, 0x01, 0xff, 0x04, 0x05, 0x30, 0x03, 0x01, 0x01, 0xff]])
        #expect(try extensions(chain.hostCertificate) == [notAuthority, keyUsage])
        let device = try extensions(chain.deviceCertificate)
        #expect(device.count == 3 && device[0] == notAuthority && device[2] == keyUsage)
        // OpenSSL's subjectKeyIdentifier=hash for this key: E5:E3:56:1F:…:21:F8:90.
        let identifier: [UInt8] = [0xe5, 0xe3, 0x56, 0x1f, 0xe3, 0x24, 0x1e, 0x09, 0x3a, 0x01, 0x6c, 0x35, 0x15, 0x79, 0xb1, 0x25, 0x67, 0x21, 0xf8, 0x90]
        #expect(device[1] == [0x30, 0x1d, 0x06, 0x03, 0x55, 0x1d, 0x0e, 0x04, 0x16, 0x04, 0x14] + identifier)
    }

    @Test func theDevicesCertificateHoldsTheDevicesKeyAndTheHostItsOwn() throws {
        let chain = try PairingCertificates(devicePublicKey: Array(Self.pkcs1.utf8), at: Self.date)
        #expect(try X509Certificate(der: Self.der(chain.deviceCertificate), path: "device").subjectPublicKeyInfo == Self.info)
        let host = try PEM.rsaPrivateKey(in: String(decoding: chain.hostPrivateKey, as: UTF8.self), path: "host")
        #expect(try X509Certificate(der: Self.der(chain.hostCertificate), path: "host").subjectPublicKeyInfo == [UInt8](host.publicKey.derRepresentation))
        #expect(chain.rootPrivateKey != chain.hostPrivateKey)
    }
}
