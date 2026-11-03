import Foundation
import NomacCore
import NomacTestSupport
import Testing
@testable import NomacSigning

/// Signing with a certificate gives what codesign gave for the same input, identity and signing
/// time (observed with `signing_experiments.py synthetic`, the identities imported into a
/// throwaway keychain). The identities are test-only: a self-signed certificate, and a leaf
/// issued by a self-made root CA, with their RSA keys, made with openssl for these tests.
@Suite struct CertificateSigningTests {
    /// "nomac Test Signing", self-signed; SHA-1 ca1008984191f0fce71eefe998fa084255e5475e.
    static let selfSigned = """
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCm2PG/4CLCkn5o
    viN2XCsfqh6+9X+WifKAQH79ywNY5LGYwtHcL8UhSQ8stUErJKL0GB8hQXS0i+iF
    D7AWnvQMbKNtlAMEqHQAtK3WoNMyyd/BNP1FHGVkPJEqJ3NtyyrEPHqDeiPexqDI
    Trj31a8kNzTIu4Lh+UC42T0XCengliYSfSfwbYaqhFar52/JQ4FNemJyPlXpNHXv
    ej+lopNTtFG3b+MMyaT4Ki+kN3i9/BPC3hna/nT4XNiJtEmD3tO9sPK8Ps3eU7GW
    zjeIf3euNNFcKIsrEO+uaW66rBsElcYfJ7Qz3eX0Vb3ymOVKnEhj+/yuWp9H9OHO
    j9NXxDODAgMBAAECggEAO/4z5wdj2EyukWEVBUEc7HTSO12w8+NERCNsxjsSSAtr
    ZH9g0GiI3HAVucCu3yF8SoLF5sJPgX/xKq86ZNfg7vq9RPB8qVcc5wgQneUUK+X0
    w9cW3pvYRVOV6u9mjOsJxKfucYogjcEkHQJZdhvqrv3+x9LMvA5Q3GaYlcklxHAE
    KV8ribTfD8dvw680ynNfcLsFGHEzh1kTuNqdd2svdNhhQXbzPYx7/8JlGtVM8L1O
    Yvv6wL10ofI65vI77vKwCy5YUnX4RAOY+G+VLwLvrAXpLkBropv4Hv8EWGinh5lk
    PB/Yc/MkHvPdUP3SXDt2F2iYTrQfuL8IKpaOMe2viQKBgQDVmsn6OXGPsa15ku2Z
    e0ReZcrZ35mWy1f+P8v1ty3JTyoBhaX0k0sRM2xEdDM9+ZUHk/7VKBXmNVvbB4ZA
    h2MKZSq8yLAb3JyWC4vaMhU7fVuUuB6Ooo1MLuitpNhE84IW1gg2WU4ksJASZ5YG
    9CjmxXcHRDKIdPKagCiijvDTDQKBgQDH9m5C1bwLx5FPJyGoZiI6E22jEGWhKOnq
    deph8IjxQbFuj1JnJEXR6pYVXkp50aR9lbEcpd6wgq6inHJKzoCOQqFENN2yvBeW
    TUxc+8SfmpEGRxg61eOLkOTegpJiROhn8yih6YOkK8vhkbDYQOY6OrVTi1RJ1ILA
    hq3s9Ty8zwKBgQCa1ukA5TEn28GHtnVb49pMn3drdkXs5Jx1pqNgDBg5rJQjpFEH
    uNoaru8VtDINA+X/J038EGHHjfh3Dr5H+pxVxb40OTpICCTOM7J+Sf3QMO/5H3qv
    JLBOgFaUwUEwwmAT07UCSLx3pjHZ1ZMQmV8o4g2Fi+8hsbzHOI28QOfb5QKBgQCB
    7gZHN0ow/UPWAr9EBNlIk0cyJX1j8onL50Kc0QaqfN0l0crhahhUBfHvgI00Cpyv
    XYzv6HeCieefkbhSE0xFI9ZV02Qat008RI3R/WYNrwl84sVDtaddEJEmZAFqCQxa
    Pw2v52O6URrxPxGB8uml/G/GEUp7jrJHFzv8NH160QKBgDSSVI1w1oPgxO87o7St
    UXVBOH/iO3E9IZLJ9tiRCFMtHnn5l1dZgQqbvFKSONRwiMT5uf1iOfpJIGmiZNfb
    OvY6lIWKmRPqGsfTBd4ICQZsfy7Pucz3rSDmjg1e3X5OTJj9IeP72pomibseJoUE
    YJdYtpxLt1ZU4+ySMFfaxNFt
    -----END PRIVATE KEY-----
    -----BEGIN CERTIFICATE-----
    MIIDETCCAfmgAwIBAgIFTk9NQUMwDQYJKoZIhvcNAQELBQAwLTEbMBkGA1UEAwwS
    bm9tYWMgVGVzdCBTaWduaW5nMQ4wDAYDVQQKDAVub21hYzAeFw0yNjEwMjEyMTQx
    MTVaFw0zNjEwMTgyMTQxMTVaMC0xGzAZBgNVBAMMEm5vbWFjIFRlc3QgU2lnbmlu
    ZzEOMAwGA1UECgwFbm9tYWMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
    AQCm2PG/4CLCkn5oviN2XCsfqh6+9X+WifKAQH79ywNY5LGYwtHcL8UhSQ8stUEr
    JKL0GB8hQXS0i+iFD7AWnvQMbKNtlAMEqHQAtK3WoNMyyd/BNP1FHGVkPJEqJ3Nt
    yyrEPHqDeiPexqDITrj31a8kNzTIu4Lh+UC42T0XCengliYSfSfwbYaqhFar52/J
    Q4FNemJyPlXpNHXvej+lopNTtFG3b+MMyaT4Ki+kN3i9/BPC3hna/nT4XNiJtEmD
    3tO9sPK8Ps3eU7GWzjeIf3euNNFcKIsrEO+uaW66rBsElcYfJ7Qz3eX0Vb3ymOVK
    nEhj+/yuWp9H9OHOj9NXxDODAgMBAAGjODA2MAwGA1UdEwEB/wQCMAAwDgYDVR0P
    AQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMDMA0GCSqGSIb3DQEBCwUA
    A4IBAQBviJaWs8j69etSTyLpsfkgBTpPX6RNAdlemnHEawhmjXuMpzxW8XjgBdw9
    PIbS3Oz2dBOTTPUqRTKcSKCQbzufVRlxjRbXOMfEF1vGg3iMR6grtGgsuplkAXkS
    L02k6IAAZRLcm2XEQMrRoUjKscdiA9aXj0kY3iT6m4OyAiqCb/Rach3QnxoTAWk1
    sH8AWxYQZBHYy4wRyhIr86G0oyJeXL3l+PhloM2lwWZ1yUxJZkv9ZdzUkd3bCG92
    aGBtSdfFAnFoh00KmIhRQrx8gkR73VbyXSIa3C+uIJRch1Y3sp6P1/hPqHJequDD
    OnOMII1WtlvpDyvs352Y4JpIYPMt
    -----END CERTIFICATE-----
    """

    /// "nomac Developer: Test (ABCDE12345)" (OU ABCDE12345) issued by "nomac Test Root CA";
    /// SHA-1 006fadae347d2076c887cf85333a2a1d4becff26.
    static let issued = """
    -----BEGIN PRIVATE KEY-----
    MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDJQI6duANwUBBa
    rXQWStfsXLlc5Sdmb1LxS9MslveAp449DYe80zCKo/XBokz3jtt1BXyEkCrGUZ1X
    rhJ3hRoNcxR5lRGC+YNcX73zhS+06rPoQ+5QORYfcGGZVcLBJLgPALHTCngsHpcK
    l8gcEKCgW/i2mCbsOnn78JyuY35uoI1+2UVVx4gBc+98S537OD3UI9O//6kF5Kdg
    ac8+ejinwkyi+K2jpUCuhSBUPBwYclKz4I3ZUr/Mf7eZvareCRgVGlOhYwzJUoo7
    4gO5OLnahR41oy1Oz6injH70oSjhuYbf7h6SVO1Cqdhtb3aUS7EFpaEQgAQbP60F
    Pw/+fGrFAgMBAAECggEALJwZwM4sPPYSWfc+1z4p1KPNFtFYxXUBvqjfG3AvVp5N
    gi0AnJN3nBOyAwT16J4K+UqJCl1mjeVDak8UmtevKbILpNOtOQoT2yMB2Pv50jGA
    RYjhR3kP9VIU4EdJT0TTY8f0ouIcNzNkqZ1xZv8si783R0o8vnpL1dPE90bonJ6n
    N5K2Fs7rYJjrARBAX6TAklyQPShpMi8tPQUxMM2EOhke31M723SOrkXHksufnzM/
    XWYE3/mz66mt3eQalZxzxJqALM2IMBTAW6xgrcWUAeGIwtUxQ6PocZ1vmIPQWN4e
    Svi11Tx4dGile73NrVEA4Yma7kyn9/9b9dKMzC9SlQKBgQD0Z1KNnMzhXdAsu2ry
    Enx38ksREp2T6Q1ZJ+cULfrtBt82gD6foMMWH3T5GjrF2GdQZsFgRlQZEdRtqgZO
    0NaTLbEn3wFM9pLkf0/ArWkz6PVnrz90orMgFfnnOhbhKxDYXia0RLG9iSSoyEP3
    GF0MPVFvF28mv/3A/B0Svlau8wKBgQDSzRc1lwVKpDLKdGjieEPv6NclcBlHPN81
    5f7FUhxGXb1gCTUtzrbHEOWChJRe2l1CnIn7eVOOwZ6OXyAUtCIfqZq/HLOa9s4X
    CneBRJ7fLNVc5CQsZrqszwGcHhTmaJDoAdKt69P4do2zGeU2b/RilVtA5pZZbIoN
    EwuQDKudZwKBgQCSxpI/VZF9LtfcZVmesxdo+Wu3fxR/RZCsoFgYOFzfiCb5Fh+F
    wggm+xFGoEf3lTTGhk9PwCy1OY33pgpPvv9+OAySQ00GqXYiH4sHzZzGffsTH53e
    L++fL1N7V9lxtGlTZ4ea7z5G81u+uTaH6GvI8/I54zrvbJG6Gi5jmUd5nQKBgDOw
    go5rd6qz1Jh8LvPJVa9QQuE1OZ2UOY931B8CYViHx9XyrA2NcJgjdoOoitEvbkrV
    I6h8OZb5ty1l+fHZsbxd1EokeY34EtTnhiI2d1Z2IeNjNdOFZSTWpahoX+uXnGCn
    gceP2ixEtb5DDUdp8Fz0Dqo9YISQ7tEB6IXr9XDlAoGBAOYajhZ7RPDumDha66u0
    Q7GbBJI8n4HdGcKotgB1EInjvrm8CHI1HXrZ8vR1yPzwSNXMiQmeFGLFOBA050xe
    YD/X+PP+NmvuRAa/c6bA4jyUkDIJaV/NAXbGCbvF4L1HtBmyv4UBGhIqfyGHQ/Bh
    DWt6fK44WY1oPH5l7UiIbLXU
    -----END PRIVATE KEY-----
    -----BEGIN CERTIFICATE-----
    MIIDZDCCAkygAwIBAgIFAQIDBAUwDQYJKoZIhvcNAQELBQAwLTEbMBkGA1UEAwwS
    bm9tYWMgVGVzdCBSb290IENBMQ4wDAYDVQQKDAVub21hYzAeFw0yNjEwMjEyMTQy
    NTZaFw0zNjEwMTgyMTQyNTZaMF8xKzApBgNVBAMMIm5vbWFjIERldmVsb3Blcjog
    VGVzdCAoQUJDREUxMjM0NSkxEzARBgNVBAsMCkFCQ0RFMTIzNDUxDjAMBgNVBAoM
    BW5vbWFjMQswCQYDVQQGEwJVUzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
    ggEBAMlAjp24A3BQEFqtdBZK1+xcuVzlJ2ZvUvFL0yyW94Cnjj0Nh7zTMIqj9cGi
    TPeO23UFfISQKsZRnVeuEneFGg1zFHmVEYL5g1xfvfOFL7Tqs+hD7lA5Fh9wYZlV
    wsEkuA8AsdMKeCwelwqXyBwQoKBb+LaYJuw6efvwnK5jfm6gjX7ZRVXHiAFz73xL
    nfs4PdQj07//qQXkp2Bpzz56OKfCTKL4raOlQK6FIFQ8HBhyUrPgjdlSv8x/t5m9
    qt4JGBUaU6FjDMlSijviA7k4udqFHjWjLU7PqKeMfvShKOG5ht/uHpJU7UKp2G1v
    dpRLsQWloRCABBs/rQU/D/58asUCAwEAAaNZMFcwDAYDVR0TAQH/BAIwADAOBgNV
    HQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwMwHwYDVR0jBBgwFoAU
    29QGvixE0l486T8+ZR6yhUiF2hIwDQYJKoZIhvcNAQELBQADggEBAAZ8pCzs8Pp5
    gAxQ/nW87RulVuo30QL3r2W78znkphimDLCOjMWsBlXjmFebYLF5cngXEIPykP2x
    DZSyEiPi9/I/+9LUdmxrrVxM/Njc/0MWRdiP2AwNxMT56LyVEytG6V8TE1mE8j+J
    jlzLkWJPAxrLqbRfrnbbk5IUSdOo9khpg6Z/WG9DCZKKVK1v/IeY/PnDMbihBrSU
    k08WewUGDMvpzcosIHoYAPvpBaAFeg4yD/SW5VPmWdVpfax41wRLkpeN6MDNVKSm
    w1tmrUcfc50x8/cfTycMX4hhx8i402Gy7chAMWxeHR25SrKyQn7bVpNH+kFbUZbR
    lBi0SC+Qpv0=
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    MIIDFzCCAf+gAwIBAgIBATANBgkqhkiG9w0BAQsFADAtMRswGQYDVQQDDBJub21h
    YyBUZXN0IFJvb3QgQ0ExDjAMBgNVBAoMBW5vbWFjMB4XDTI2MTAyMTIxNDI1NloX
    DTM2MTAxODIxNDI1NlowLTEbMBkGA1UEAwwSbm9tYWMgVGVzdCBSb290IENBMQ4w
    DAYDVQQKDAVub21hYzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOGS
    ftB3bU2X8Uti+6xXj5gu9EyJ6kabLCG/vzbK9TI0+KtqiY8XEEoCRQ69OYKOFTxw
    8cv89VEEEtkxgKuZSDdxMUqflO6oSJr0YwLPNKW3YM98e8Vlp6LCAVv0Z+Y0pK3/
    TuVj+PZ2qVAw+mVFYCs9bM0e64fUNPugWDxjzlW2DEpn4bs8TK/zCxvs/cCKLG27
    YKaA1QuQPoXkeH9QGxaExfp7+f0RFHFDh3wph2ixcOKyzckf04SMgIXggvLiPYLj
    9iyGZE8+0kGynckKoMkoxHmWe377S8JanAFXGvjPKnjWVI7FCqs0psYzChVg5vmJ
    hbZp8JmxvspsTNchqUUCAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8B
    Af8EBAMCAQYwHQYDVR0OBBYEFNvUBr4sRNJePOk/PmUesoVIhdoSMA0GCSqGSIb3
    DQEBCwUAA4IBAQClKz2lT9mhSulfaldiRzsoY2499hh5AgEJWGBiPL6XNyBokSL9
    ijLSbSk0GdRRXALRL/HPvFMj0/eNYFmsDA+8A+qB8cSvXJbUwQkLqgv8f6zGkMCA
    PCETRmDnLMiMMLt3O1jLutRaKtRljwHTTUsY62Cyv6OGSyAVBPEtL65y6TeS82s+
    mkX0vHle1oJMcRU8qFgEOt3zObC7hZ2ssAicEZWlXcE5dD2B+cvSVmvD0tIX+nzp
    ixVZML1qDmuyiLN1e+OQpBOQXK7wdPMuSxS23yzabH92cpDcMXvywFR70WBRDasg
    Ky4Hjr4ic8dNsSwQiHsZL2PeHF1lJRIBhK6i
    -----END CERTIFICATE-----
    """

    /// The key of `selfSigned` with two more self-signed certificates, "nomac Exact" (SHA-1
    /// 474b955fb4a897158833e81c5231be41819fafe8) and "nomac Exact Longer" (SHA-1
    /// 8c4039c702cbb31fb859b8fc9ddd031bbde8d1f4), in that order: names one of them contains.
    static let similarNames = selfSigned.components(separatedBy: "-----BEGIN CERTIFICATE-----")[0] + """
    -----BEGIN CERTIFICATE-----
    MIIDQzCCAiugAwIBAgIFTk9NQUMwDQYJKoZIhvcNAQELBQAwJjEUMBIGA1UEAwwL
    bm9tYWMgRXhhY3QxDjAMBgNVBAoMBW5vbWFjMB4XDTI2MTAyMTIzNTYyOVoXDTM2
    MTAxODIzNTYyOVowJjEUMBIGA1UEAwwLbm9tYWMgRXhhY3QxDjAMBgNVBAoMBW5v
    bWFjMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAptjxv+AiwpJ+aL4j
    dlwrH6oevvV/lonygEB+/csDWOSxmMLR3C/FIUkPLLVBKySi9BgfIUF0tIvohQ+w
    Fp70DGyjbZQDBKh0ALSt1qDTMsnfwTT9RRxlZDyRKidzbcsqxDx6g3oj3sagyE64
    99WvJDc0yLuC4flAuNk9Fwnp4JYmEn0n8G2GqoRWq+dvyUOBTXpicj5V6TR173o/
    paKTU7RRt2/jDMmk+CovpDd4vfwTwt4Z2v50+FzYibRJg97TvbDyvD7N3lOxls43
    iH93rjTRXCiLKxDvrmluuqwbBJXGHye0M93l9FW98pjlSpxIY/v8rlqfR/Thzo/T
    V8QzgwIDAQABo3gwdjAdBgNVHQ4EFgQU/ni3JcmoI60MsKBKCAjnZl+YtQIwHwYD
    VR0jBBgwFoAU/ni3JcmoI60MsKBKCAjnZl+YtQIwDAYDVR0TAQH/BAIwADAOBgNV
    HQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwMwDQYJKoZIhvcNAQEL
    BQADggEBAEDyU7UagslPsJwuwMh5wpgt4B8bP7zPnXYvS0EzPE85yrzzXg5zq4um
    hsg6IHJFxaffVyneoTC9TV7zrpSctCt3dI6J9SN9mywA6y3MwQv/ve7I3R2RIfdk
    Alc6Cb+lCa3j0qziX/ePL5xYbBduZTk1Uv7gBIVobZVFaj/OoFodsidkJZ6GlTxz
    Nmc/xwbsgmckD7YnnEywIUjTPXbTKuEegFY/hGP/LkC7ikHqcJ+1q1Wob50NzZ/B
    rBxwNt6D8f08tXtKpBdqDOzgDi8j6KIiYR0BJ699b2NybRszjrM0q1sWvOCTEVfZ
    MbEtB1w19nTl2uUfiWAD9waBauVuHUs=
    -----END CERTIFICATE-----
    -----BEGIN CERTIFICATE-----
    MIIDUTCCAjmgAwIBAgIFTk9NQUMwDQYJKoZIhvcNAQELBQAwLTEbMBkGA1UEAwwS
    bm9tYWMgRXhhY3QgTG9uZ2VyMQ4wDAYDVQQKDAVub21hYzAeFw0yNjEwMjEyMzU2
    MjlaFw0zNjEwMTgyMzU2MjlaMC0xGzAZBgNVBAMMEm5vbWFjIEV4YWN0IExvbmdl
    cjEOMAwGA1UECgwFbm9tYWMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
    AQCm2PG/4CLCkn5oviN2XCsfqh6+9X+WifKAQH79ywNY5LGYwtHcL8UhSQ8stUEr
    JKL0GB8hQXS0i+iFD7AWnvQMbKNtlAMEqHQAtK3WoNMyyd/BNP1FHGVkPJEqJ3Nt
    yyrEPHqDeiPexqDITrj31a8kNzTIu4Lh+UC42T0XCengliYSfSfwbYaqhFar52/J
    Q4FNemJyPlXpNHXvej+lopNTtFG3b+MMyaT4Ki+kN3i9/BPC3hna/nT4XNiJtEmD
    3tO9sPK8Ps3eU7GWzjeIf3euNNFcKIsrEO+uaW66rBsElcYfJ7Qz3eX0Vb3ymOVK
    nEhj+/yuWp9H9OHOj9NXxDODAgMBAAGjeDB2MB0GA1UdDgQWBBT+eLclyagjrQyw
    oEoICOdmX5i1AjAfBgNVHSMEGDAWgBT+eLclyagjrQywoEoICOdmX5i1AjAMBgNV
    HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAKBggrBgEFBQcD
    AzANBgkqhkiG9w0BAQsFAAOCAQEAQsUbpM6SQhoSc4vlWUMXNZspM4IWlskJ6Jvn
    sM4cow/ykSoTS6rqfiLWaOQQbPupIYITucBfrdxacev6bYKs0o2jv5yuMH0oBFTP
    gBmFOvpqJoEquzOMRuYEqF19q3lhuWO84DrAI3WhlqcrEt9yXa18P1yzcb1gOK5g
    0YFQLdWzi2MStpi14pNmiJrj62W2roqbJPC+0P6MN/OkijPuklwcny+A3ne4DAfD
    XYyKXDSPX6dR1GmsnD3oPTz3CLzY9AdMn+GnnG9mdXgbVGPiIkcdVpbgFcD7vgDZ
    fwvv2uJXTyjLdZoa+hRqKB/83c4N99OPfIKISHMqDSq+DaWKkQ==
    -----END CERTIFICATE-----
    """

    static func sign(_ name: String, identity: String, pem: String, time: String, input: (URL) throws -> URL, _ arguments: [String],
                     entitlements: String? = nil) throws -> [String: String] {
        let temporary = try TemporaryDirectory(prefix: "nomac-certificate")
        let directory = URL(fileURLWithPath: temporary.path)
        let keychain = directory.appendingPathComponent("identity.pem")
        try Data(pem.utf8).write(to: keychain)
        let product = try input(directory)
        var arguments = arguments + ["--sign", identity, "--keychain", keychain.path, "--timestamp=none"]
        var entitlementsURL: URL?
        if let entitlements {
            entitlementsURL = directory.appendingPathComponent("entitlements.plist")
            try Data(entitlements.utf8).write(to: entitlementsURL!)
            arguments += ["--entitlements", entitlementsURL!.path]
        }
        try SyntheticBundle.observe(product, named: name, arguments: arguments, entitlements: entitlementsURL)
        let formatter = ISO8601DateFormatter()
        for var request in try CodesignArguments.parse(arguments + [product.path]) {
            request.signingTime = formatter.date(from: time)
            _ = try CodeSigner.sign(request)
        }
        return try SyntheticBundle.digests(of: product)
    }

    @Test func signsWithAnIssuedCertificate() throws {
        let digests = try Self.sign("certificate-chain", identity: "006FADAE347D2076C887CF85333A2A1D4BECFF26", pem: Self.issued,
                                    time: "2026-10-21T21:49:04Z", input: CodeSignerTests.file(SyntheticMachO.machO(seed: 7), named: "tool"), ["--force"])
        #expect(digests == ["": "0f87f85e44bb7213d892acc0f475445ec9301d077e813ff8b2a6ab43f27e3d8f"])
    }

    /// A static framework (detached signature, its binary as the code) and an asset pack (no
    /// executable) signed with the Apple-shaped identity: a version 0x20100 code directory
    /// without flags, the designated requirement in CodeRequirements and the CMS in
    /// CodeSignature; with --generate-pre-encrypt-hashes, version 0x20500.
    @Test func signsDetachedBundlesWithACertificate() throws {
        let framework = try Self.sign("certificate-static", identity: "EF637C7AB75E0067594DF81B2D25E6AD1818024A", pem: TestIdentities.appleShaped,
                                      time: "2026-10-31T01:12:51Z", input: SyntheticBundle.staticFramework, ["--force"])
        let preEncrypt = try Self.sign("certificate-static-pre-encrypt", identity: "EF637C7AB75E0067594DF81B2D25E6AD1818024A",
                                       pem: TestIdentities.appleShaped, time: "2026-10-31T01:12:53Z", input: SyntheticBundle.staticFramework,
                                       ["--generate-pre-encrypt-hashes", "--force"])
        let pack = try Self.sign("certificate-asset-pack", identity: "EF637C7AB75E0067594DF81B2D25E6AD1818024A", pem: TestIdentities.appleShaped,
                                 time: "2026-10-31T01:12:49Z", input: SyntheticBundle.assetPack, ["--force"])
        #expect(framework.filter { $0.key.hasPrefix("_CodeSignature/") } == [
            "_CodeSignature/CodeDirectory": "d7243760d7d6949ec9983d29d35c17819f368503073a95a7934c05c9d3c314d5",
            "_CodeSignature/CodeRequirements": "7b287eefe8b53796384539f627f9dd7e4e965f0ef18c39b9d8228c7ab29a7e92",
            "_CodeSignature/CodeResources": "6f2b17be07a1af376e787f45f75bd0f91ad00260b14f352211129842814d92c7",
            "_CodeSignature/CodeSignature": "6bb4f667693106cabb6232d69bc5118440d4d235f439c74a60237dd5050121ec",
        ])
        #expect(preEncrypt.filter { $0.key.hasPrefix("_CodeSignature/") } == [
            "_CodeSignature/CodeDirectory": "f8f78ab78fb2a158ababd3ce9a60cff7a896c4b2aab707111d16ff2a1d724c19",
            "_CodeSignature/CodeRequirements": "7b287eefe8b53796384539f627f9dd7e4e965f0ef18c39b9d8228c7ab29a7e92",
            "_CodeSignature/CodeResources": "6f2b17be07a1af376e787f45f75bd0f91ad00260b14f352211129842814d92c7",
            "_CodeSignature/CodeSignature": "2e43d48099946a991a9188bd3d7cf5b3c99f6f43b8bc181c15e35e18507d9b1d",
        ])
        #expect(pack.filter { $0.key.hasPrefix("_CodeSignature/") } == [
            "_CodeSignature/CodeDirectory": "7e053b2bda9bcba4c3d3e65335bade0200c32e1375389d964aa8c9748c06847d",
            "_CodeSignature/CodeRequirements": "f08ef4c03622601507fc13ada4091304ae66ea128348ab4b1ae100c6e28509a2",
            "_CodeSignature/CodeResources": "f5ebf05b87c4ce4d1e38c3779c40023f6f0267a59c38d03f2a0ad58d01ab5968",
            "_CodeSignature/CodeSignature": "2e6d6b387f2b3b2dae3129e5088816a11a0e3b377cc27e619e2d7cf0753e9608",
        ])
    }

    /// A watch app's executable (arm64 for watchOS 26.0, arm64_32 for 11.0) has a SHA-1 code
    /// directory in each slice beside the SHA-256 one.
    @Test func signsAWatchExecutableWithACertificate() throws {
        let file = SyntheticMachO.universal([SyntheticMachO.machO(platform: 4, minimumOS: 26 << 16, seed: 19),
                                             SyntheticMachO.machO(arm64_32: true, platform: 4, minimumOS: 11 << 16, seed: 20)])
        let digests = try Self.sign("certificate-watch", identity: "006FADAE347D2076C887CF85333A2A1D4BECFF26", pem: Self.issued,
                                    time: "2026-10-22T10:26:27Z", input: CodeSignerTests.file(file, named: "Watch"), ["--force"])
        #expect(digests == ["": "9fa17adfdb99a6acd5ea26ce2291e973540fae419c12f8a30a8744b681e76ddc"])
    }

    @Test func signsABundleWithASelfSignedCertificate() throws {
        let digests = try Self.sign("certificate-bundle", identity: "nomac Test Signing", pem: Self.selfSigned, time: "2026-10-21T21:49:04Z",
                                    input: SyntheticBundle.application, ["--force", "--generate-entitlement-der"],
                                    entitlements: CodeSignerTests.entitlements)
        #expect(digests["Foo"] == "6ae16a9875254fe6c7f6e72b27a19776abf26a7c1bd2b5c7877ad8911a059861")
        #expect(digests["_CodeSignature/CodeResources"] == "85c39ab86b5db6f8b3c61038f60b2a2aaef04d7b8234ec3ada549681dd2400b6")
    }

    @Test func needsAChainToASelfSignedRoot() throws {
        let leafOnly = Self.issued.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropLast().joined(separator: "-----BEGIN CERTIFICATE-----")
        #expect(throws: NomacError("unable to build chain to self-signed root for signer \"nomac Developer: Test (ABCDE12345)\"",
                                   notes: ["errSecInternalComponent"])) {
            _ = try Self.sign("certificate-no-root", identity: "006fadae347d2076c887cf85333a2a1d4becff26", pem: leafOnly,
                              time: "2026-10-21T21:49:04Z", input: CodeSignerTests.file(SyntheticMachO.machO(seed: 7), named: "tool"), ["--force"])
        }
    }

    /// A chain not anchored at Apple's root keeps the non-Apple requirement and no team
    /// identifier, whatever its shape: the anchor is the leaf, the last certificate up the chain
    /// with the leaf's organization.
    @Test func signsWithAnAppleShapedChainFromAnotherRoot() throws {
        let digests = try Self.sign("certificate-apple-shaped", identity: "Apple Development: nomac Test (ABCDE12345)", pem: TestIdentities.appleShaped,
                                    time: "2026-10-22T10:10:53Z", input: CodeSignerTests.file(SyntheticMachO.machO(seed: 18), named: "tool"),
                                    ["--force"])
        #expect(digests == ["": "f0f63b4d24967894b45e14c7e7806597ccc0af8f9f5870fad95377da1e641842"])
    }

    /// An Apple Development signature (observed privately with an Apple-issued identity: nomac's
    /// file, given codesign's RSA value, is codesign's byte for byte, and both verify), here with
    /// the self-made chain of the same shape taken as anchored at Apple's root: the iOS designated
    /// requirement names the leaf's common name and the intermediate's marker, and the code
    /// directory carries the leaf's organizational unit as team identifier.
    @Test func signsAsAnIOSChainToApplesRoot() throws {
        let temporary = try TemporaryDirectory(prefix: "nomac-certificate")
        let pemPath = temporary.path + "/identity.pem"
        try Data(TestIdentities.appleShaped.utf8).write(to: URL(fileURLWithPath: pemPath))
        let shaped = try SigningIdentity(named: "Apple Development: nomac Test (ABCDE12345)", pem: TestIdentities.appleShaped, path: pemPath)
        let identity = SigningIdentity(chain: shaped.chain, appleRoots: [shaped.chain.last!.sha1Hex], sign: shaped.sign)
        #expect(identity.isApple && identity.isIOSChain)
        let tool = try CodeSignerTests.file(SyntheticMachO.machO(seed: 18), named: "tool")(URL(fileURLWithPath: temporary.path))
        _ = try CodeSigner.sign(CodeSigner.Request(path: tool.path, identity: "-", force: true), identity: identity)
        #expect(try CodeSigner.designatedRequirement(of: tool.path).output == """
            designated => identifier tool and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: nomac Test \
            (ABCDE12345)" and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */

            """)
        let image = try MachOContainer(bytes: [UInt8](try Data(contentsOf: tool)), path: tool.path).slices[0].image
        let directory = try #require(try CodeSigner.ExistingSignature(image: image, path: tool.path)).codeDirectory
        let teamOffset = Int(directory[48..<52].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        #expect(String(decoding: directory[teamOffset...].prefix { $0 != 0 }, as: UTF8.self) == "ABCDE12345")
    }

    /// codesign prefers a common name equal to the name given, ignoring case, to the ones that
    /// contain it.
    @Test func prefersTheCommonNameEqualToTheName() throws {
        let digests = try Self.sign("certificate-exact-name", identity: "NOMAC EXACT", pem: Self.similarNames, time: "2026-10-22T00:05:15Z",
                                    input: CodeSignerTests.file(SyntheticMachO.machO(seed: 7), named: "tool"), ["--force"])
        #expect(digests == ["": "381905de70f15c4f98f0c1a898c6f16f9289d6d63117affb7ac2f4ada9e0206b"])
    }

    @Test func takesTheOnlyCommonNameContainingTheName() throws {
        let digests = try Self.sign("certificate-partial-name", identity: "longer", pem: Self.similarNames, time: "2026-10-22T00:05:19Z",
                                    input: CodeSignerTests.file(SyntheticMachO.machO(seed: 7), named: "tool"), ["--force"])
        #expect(digests == ["": "2f47fca4300ce3ac24420901368e183bb579f6740ea4101d8b9ca2f3a4b269a4"])
    }

    @Test func failsWhenSeveralCommonNamesContainTheName() throws {
        #expect(throws: NomacError("ambiguous (matches \"nomac Exact Longer\" and \"nomac Exact\" in identity.pem)", path: "xact")) {
            _ = try SigningIdentity(named: "xact", pem: Self.similarNames, path: "identity.pem")
        }
        _ = try? Self.sign("certificate-ambiguous-name", identity: "xact", pem: Self.similarNames, time: "2026-10-21T21:49:04Z",
                           input: CodeSignerTests.file(SyntheticMachO.machO(seed: 7), named: "tool"), ["--force"])
    }
}
