# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestPKeyRSA < OpenSSL::PKeyTestCase
  def test_no_private_exp
    key = OpenSSL::PKey::RSA.new
    rsa = Fixtures.pkey("rsa2048")
    key.set_key(rsa.n, rsa.e, nil)
    key.set_factors(rsa.p, rsa.q)
    assert_raise(OpenSSL::PKey::RSAError){ key.private_encrypt("foo") }
    assert_raise(OpenSSL::PKey::RSAError){ key.private_decrypt("foo") }
  end if !openssl?(3, 0, 0) # Impossible state in OpenSSL 3.0

  def test_private
    key = Fixtures.pkey("rsa2048")

    # Generated by DER
    key2 = OpenSSL::PKey::RSA.new(key.to_der)
    assert(key2.private?)

    # public key
    key3 = key.public_key
    assert(!key3.private?)

    # Generated by public key DER
    key4 = OpenSSL::PKey::RSA.new(key3.to_der)
    assert(!key4.private?)
    rsa1024 = Fixtures.pkey("rsa1024")

    if !openssl?(3, 0, 0)
      key = OpenSSL::PKey::RSA.new
      # Generated by RSA#set_key
      key5 = OpenSSL::PKey::RSA.new
      key5.set_key(rsa1024.n, rsa1024.e, rsa1024.d)
      assert(key5.private?)

      # Generated by RSA#set_key, without d
      key6 = OpenSSL::PKey::RSA.new
      key6.set_key(rsa1024.n, rsa1024.e, nil)
      assert(!key6.private?)
    end
  end

  def test_new
    key = OpenSSL::PKey::RSA.new(2048)
    assert_equal 2048, key.n.num_bits
    assert_equal 65537, key.e
    assert_not_nil key.d
    assert(key.private?)
  end

  def test_new_public_exponent
    # At least 2024-bits RSA key are required in FIPS.
    omit_on_fips

    # Specify public exponent
    key = OpenSSL::PKey::RSA.new(512, 3)
    assert_equal 512, key.n.num_bits
    assert_equal 3, key.e
  end

  def test_s_generate
    key1 = OpenSSL::PKey::RSA.generate(2048)
    assert_equal 2048, key1.n.num_bits
    assert_equal 65537, key1.e
  end

  def test_s_generate_public_exponent
    # At least 2024-bits RSA key are required in FIPS.
    omit_on_fips

    # Specify public exponent
    key = OpenSSL::PKey::RSA.generate(512, 3)
    assert_equal 512, key.n.num_bits
    assert_equal 3, key.e
  end

  def test_new_break
    assert_nil(OpenSSL::PKey::RSA.new(2048) { break })
    assert_raise(RuntimeError) do
      OpenSSL::PKey::RSA.new(2048) { raise }
    end
  end

  def test_sign_verify
    rsa = Fixtures.pkey("rsa2048")
    data = "Sign me!"
    signature = rsa.sign("SHA256", data)
    assert_equal true, rsa.verify("SHA256", signature, data)

    signature0 = (<<~'end;').unpack1("m")
      ooy49i8aeFtkDYUU0RPDsEugGiNw4lZxpbQPnIwtdftEkka945IqKZ/MY3YSw7wKsvBZeaTy8GqL
      lSWLThsRFDV+UUS9zUBbQ9ygNIT8OjdV+tNL63ZpKGprczSnw4F05MQIpajNRud/8jiI9rf+Wysi
      WwXecjMl2FlXlLJHY4PFQZU5TiametB4VCQRMcjLo1uf26u/yRpiGaYyqn5vxs0SqNtUDM1UL6x4
      NHCAdqLjuFRQPjYp1vGLD3eSl4061pS8x1NVap3YGbYfGUyzZO4VfwFwf1jPdhp/OX/uZw4dGB2H
      gSK+q1JiDFwEE6yym5tdKovL1g1NhFYHF6gkZg==
    end;
    assert_equal true, rsa.verify("SHA256", signature0, data)
    signature1 = signature0.succ
    assert_equal false, rsa.verify("SHA256", signature1, data)
  end

  def test_sign_verify_options
    key = Fixtures.pkey("rsa2048")
    data = "Sign me!"
    pssopts = {
      "rsa_padding_mode" => "pss",
      "rsa_pss_saltlen" => 20,
      "rsa_mgf1_md" => "SHA1"
    }
    sig_pss = key.sign("SHA256", data, pssopts)
    assert_equal 256, sig_pss.bytesize
    assert_equal true, key.verify("SHA256", sig_pss, data, pssopts)
    assert_equal true, key.verify_pss("SHA256", sig_pss, data,
                                      salt_length: 20, mgf1_hash: "SHA1")
    # Defaults to PKCS #1 v1.5 padding => verification failure
    assert_equal false, key.verify("SHA256", sig_pss, data)

    # option type check
    assert_raise_with_message(TypeError, /expected Hash/) {
      key.sign("SHA256", data, ["x"])
    }
  end

  def test_sign_verify_raw
    key = Fixtures.pkey("rsa-1")
    data = "Sign me!"
    hash = OpenSSL::Digest.digest("SHA256", data)
    signature = key.sign_raw("SHA256", hash)
    assert_equal true, key.verify_raw("SHA256", signature, hash)
    assert_equal true, key.verify("SHA256", signature, data)

    # Too long data
    assert_raise(OpenSSL::PKey::PKeyError) {
      key.sign_raw("SHA1", "x" * (key.n.num_bytes + 1))
    }

    # With options
    pssopts = {
      "rsa_padding_mode" => "pss",
      "rsa_pss_saltlen" => 20,
      "rsa_mgf1_md" => "SHA256"
    }
    sig_pss = key.sign_raw("SHA256", hash, pssopts)
    assert_equal true, key.verify("SHA256", sig_pss, data, pssopts)
    assert_equal true, key.verify_raw("SHA256", sig_pss, hash, pssopts)
  end

  def test_sign_verify_raw_legacy
    key = Fixtures.pkey("rsa-1")
    bits = key.n.num_bits

    # Need right size for raw mode
    plain0 = "x" * (bits/8)
    cipher = key.private_encrypt(plain0, OpenSSL::PKey::RSA::NO_PADDING)
    plain1 = key.public_decrypt(cipher, OpenSSL::PKey::RSA::NO_PADDING)
    assert_equal(plain0, plain1)

    # Need smaller size for pkcs1 mode
    plain0 = "x" * (bits/8 - 11)
    cipher1 = key.private_encrypt(plain0, OpenSSL::PKey::RSA::PKCS1_PADDING)
    plain1 = key.public_decrypt(cipher1, OpenSSL::PKey::RSA::PKCS1_PADDING)
    assert_equal(plain0, plain1)

    cipherdef = key.private_encrypt(plain0) # PKCS1_PADDING is default
    plain1 = key.public_decrypt(cipherdef)
    assert_equal(plain0, plain1)
    assert_equal(cipher1, cipherdef)

    # Failure cases
    assert_raise(ArgumentError){ key.private_encrypt() }
    assert_raise(ArgumentError){ key.private_encrypt("hi", 1, nil) }
    assert_raise(OpenSSL::PKey::RSAError){ key.private_encrypt(plain0, 666) }
  end


  def test_verify_empty_rsa
    rsa = OpenSSL::PKey::RSA.new
    assert_raise(OpenSSL::PKey::PKeyError, "[Bug #12783]") {
      rsa.verify("SHA1", "a", "b")
    }
  end

  def test_sign_verify_pss
    key = Fixtures.pkey("rsa2048")
    data = "Sign me!"
    invalid_data = "Sign me?"

    signature = key.sign_pss("SHA256", data, salt_length: 20, mgf1_hash: "SHA1")
    assert_equal 256, signature.bytesize
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: 20, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: :auto, mgf1_hash: "SHA1")
    assert_equal false,
      key.verify_pss("SHA256", signature, invalid_data, salt_length: 20, mgf1_hash: "SHA1")

    signature = key.sign_pss("SHA256", data, salt_length: :digest, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: 32, mgf1_hash: "SHA1")
    assert_equal true,
      key.verify_pss("SHA256", signature, data, salt_length: :auto, mgf1_hash: "SHA1")
    assert_equal false,
      key.verify_pss("SHA256", signature, data, salt_length: 20, mgf1_hash: "SHA1")

    # The sign_pss with `salt_length: :max` raises the "invalid salt length"
    # error in FIPS. We need to skip the tests in FIPS.
    # According to FIPS 186-5 section 5.4, the salt length shall be between zero
    # and the output block length of the digest function (inclusive).
    #
    # FIPS 186-5 section 5.4 PKCS #1
    # https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-5.pdf
    unless OpenSSL.fips_mode
      signature = key.sign_pss("SHA256", data, salt_length: :max, mgf1_hash: "SHA1")
      # Should verify on the following salt_length (sLen).
      # sLen <= emLen (octat) - 2 - hLen (octet) = 2048 / 8 - 2 - 256 / 8 = 222
      # https://datatracker.ietf.org/doc/html/rfc8017#section-9.1.1
      assert_equal true,
        key.verify_pss("SHA256", signature, data, salt_length: 222, mgf1_hash: "SHA1")
      assert_equal true,
        key.verify_pss("SHA256", signature, data, salt_length: :auto, mgf1_hash: "SHA1")
    end

    assert_raise(OpenSSL::PKey::RSAError) {
      key.sign_pss("SHA256", data, salt_length: 223, mgf1_hash: "SHA1")
    }
  end

  def test_encrypt_decrypt
    rsapriv = Fixtures.pkey("rsa-1")
    rsapub = OpenSSL::PKey.read(rsapriv.public_to_der)

    # Defaults to PKCS #1 v1.5
    raw = "data"
    # According to the NIST SP 800-131A Rev. 2 section 6, PKCS#1 v1.5 padding is
    # not permitted for key agreement and key transport using RSA in FIPS.
    # https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-131Ar2.pdf
    unless OpenSSL.fips_mode
      enc = rsapub.encrypt(raw)
      assert_equal raw, rsapriv.decrypt(enc)
    end

    # Invalid options
    assert_raise(OpenSSL::PKey::PKeyError) {
      rsapub.encrypt(raw, { "nonexistent" => "option" })
    }
  end

  def test_encrypt_decrypt_legacy
    rsapriv = Fixtures.pkey("rsa-1")
    rsapub = OpenSSL::PKey.read(rsapriv.public_to_der)

    # Defaults to PKCS #1 v1.5
    unless OpenSSL.fips_mode
      raw = "data"
      enc_legacy = rsapub.public_encrypt(raw)
      assert_equal raw, rsapriv.decrypt(enc_legacy)
      enc_new = rsapub.encrypt(raw)
      assert_equal raw, rsapriv.private_decrypt(enc_new)
    end

    # OAEP with default parameters
    raw = "data"
    enc_legacy = rsapub.public_encrypt(raw, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
    assert_equal raw, rsapriv.decrypt(enc_legacy, { "rsa_padding_mode" => "oaep" })
    enc_new = rsapub.encrypt(raw, { "rsa_padding_mode" => "oaep" })
    assert_equal raw, rsapriv.private_decrypt(enc_legacy, OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING)
  end

  def test_export
    rsa1024 = Fixtures.pkey("rsa1024")

    pub = OpenSSL::PKey.read(rsa1024.public_to_der)
    assert_not_equal rsa1024.export, pub.export
    assert_equal rsa1024.public_to_pem, pub.export

    # PKey is immutable in OpenSSL >= 3.0
    if !openssl?(3, 0, 0)
      key = OpenSSL::PKey::RSA.new

      # key has only n, e and d
      key.set_key(rsa1024.n, rsa1024.e, rsa1024.d)
      assert_equal rsa1024.public_key.export, key.export

      # key has only n, e, d, p and q
      key.set_factors(rsa1024.p, rsa1024.q)
      assert_equal rsa1024.public_key.export, key.export

      # key has n, e, d, p, q, dmp1, dmq1 and iqmp
      key.set_crt_params(rsa1024.dmp1, rsa1024.dmq1, rsa1024.iqmp)
      assert_equal rsa1024.export, key.export
    end
  end

  def test_to_der
    rsa1024 = Fixtures.pkey("rsa1024")

    pub = OpenSSL::PKey.read(rsa1024.public_to_der)
    assert_not_equal rsa1024.to_der, pub.to_der
    assert_equal rsa1024.public_to_der, pub.to_der

    # PKey is immutable in OpenSSL >= 3.0
    if !openssl?(3, 0, 0)
      key = OpenSSL::PKey::RSA.new

      # key has only n, e and d
      key.set_key(rsa1024.n, rsa1024.e, rsa1024.d)
      assert_equal rsa1024.public_key.to_der, key.to_der

      # key has only n, e, d, p and q
      key.set_factors(rsa1024.p, rsa1024.q)
      assert_equal rsa1024.public_key.to_der, key.to_der

      # key has n, e, d, p, q, dmp1, dmq1 and iqmp
      key.set_crt_params(rsa1024.dmp1, rsa1024.dmq1, rsa1024.iqmp)
      assert_equal rsa1024.to_der, key.to_der
    end
  end

  def test_RSAPrivateKey
    rsa = Fixtures.pkey("rsa2048")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(0),
      OpenSSL::ASN1::Integer(rsa.n),
      OpenSSL::ASN1::Integer(rsa.e),
      OpenSSL::ASN1::Integer(rsa.d),
      OpenSSL::ASN1::Integer(rsa.p),
      OpenSSL::ASN1::Integer(rsa.q),
      OpenSSL::ASN1::Integer(rsa.dmp1),
      OpenSSL::ASN1::Integer(rsa.dmq1),
      OpenSSL::ASN1::Integer(rsa.iqmp)
    ])
    key = OpenSSL::PKey::RSA.new(asn1.to_der)
    assert_predicate key, :private?
    assert_same_rsa rsa, key

    pem = <<~EOF
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEAuV9ht9J7k4NBs38jOXvvTKY9gW8nLICSno5EETR1cuF7i4pN
    s9I1QJGAFAX0BEO4KbzXmuOvfCpD3CU+Slp1enenfzq/t/e/1IRW0wkJUJUFQign
    4CtrkJL+P07yx18UjyPlBXb81ApEmAB5mrJVSrWmqbjs07JbuS4QQGGXLc+Su96D
    kYKmSNVjBiLxVVSpyZfAY3hD37d60uG+X8xdW5v68JkRFIhdGlb6JL8fllf/A/bl
    NwdJOhVr9mESHhwGjwfSeTDPfd8ZLE027E5lyAVX9KZYcU00mOX+fdxOSnGqS/8J
    DRh0EPHDL15RcJjV2J6vZjPb0rOYGDoMcH+94wIDAQABAoIBAAzsamqfYQAqwXTb
    I0CJtGg6msUgU7HVkOM+9d3hM2L791oGHV6xBAdpXW2H8LgvZHJ8eOeSghR8+dgq
    PIqAffo4x1Oma+FOg3A0fb0evyiACyrOk+EcBdbBeLo/LcvahBtqnDfiUMQTpy6V
    seSoFCwuN91TSCeGIsDpRjbG1vxZgtx+uI+oH5+ytqJOmfCksRDCkMglGkzyfcl0
    Xc5CUhIJ0my53xijEUQl19rtWdMnNnnkdbG8PT3LZlOta5Do86BElzUYka0C6dUc
    VsBDQ0Nup0P6rEQgy7tephHoRlUGTYamsajGJaAo1F3IQVIrRSuagi7+YpSpCqsW
    wORqorkCgYEA7RdX6MDVrbw7LePnhyuaqTiMK+055/R1TqhB1JvvxJ1CXk2rDL6G
    0TLHQ7oGofd5LYiemg4ZVtWdJe43BPZlVgT6lvL/iGo8JnrncB9Da6L7nrq/+Rvj
    XGjf1qODCK+LmreZWEsaLPURIoR/Ewwxb9J2zd0CaMjeTwafJo1CZvcCgYEAyCgb
    aqoWvUecX8VvARfuA593Lsi50t4MEArnOXXcd1RnXoZWhbx5rgO8/ATKfXr0BK/n
    h2GF9PfKzHFm/4V6e82OL7gu/kLy2u9bXN74vOvWFL5NOrOKPM7Kg+9I131kNYOw
    Ivnr/VtHE5s0dY7JChYWE1F3vArrOw3T00a4CXUCgYEA0SqY+dS2LvIzW4cHCe9k
    IQqsT0yYm5TFsUEr4sA3xcPfe4cV8sZb9k/QEGYb1+SWWZ+AHPV3UW5fl8kTbSNb
    v4ng8i8rVVQ0ANbJO9e5CUrepein2MPL0AkOATR8M7t7dGGpvYV0cFk8ZrFx0oId
    U0PgYDotF/iueBWlbsOM430CgYEAqYI95dFyPI5/AiSkY5queeb8+mQH62sdcCCr
    vd/w/CZA/K5sbAo4SoTj8dLk4evU6HtIa0DOP63y071eaxvRpTNqLUOgmLh+D6gS
    Cc7TfLuFrD+WDBatBd5jZ+SoHccVrLR/4L8jeodo5FPW05A+9gnKXEXsTxY4LOUC
    9bS4e1kCgYAqVXZh63JsMwoaxCYmQ66eJojKa47VNrOeIZDZvd2BPVf30glBOT41
    gBoDG3WMPZoQj9pb7uMcrnvs4APj2FIhMU8U15LcPAj59cD6S6rWnAxO8NFK7HQG
    4Jxg3JNNf8ErQoCHb1B3oVdXJkmbJkARoDpBKmTCgKtP8ADYLmVPQw==
    -----END RSA PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem)
    assert_same_rsa rsa, key

    assert_equal asn1.to_der, rsa.to_der
    assert_equal pem, rsa.export

    # Unknown PEM prepended
    cert = issue_cert(OpenSSL::X509::Name.new([["CN", "nobody"]]), rsa, 1, [], nil, nil)
    str = cert.to_text + cert.to_pem + rsa.to_pem
    key = OpenSSL::PKey::RSA.new(str)
    assert_same_rsa rsa, key
  end

  def test_RSAPrivateKey_encrypted
    omit_on_fips

    rsa1024 = Fixtures.pkey("rsa1024")
    # key = abcdef
    pem = <<~EOF
    -----BEGIN RSA PRIVATE KEY-----
    Proc-Type: 4,ENCRYPTED
    DEK-Info: AES-128-CBC,733F5302505B34701FC41F5C0746E4C0

    zgJniZZQfvv8TFx3LzV6zhAQVayvQVZlAYqFq2yWbbxzF7C+IBhKQle9IhUQ9j/y
    /jkvol550LS8vZ7TX5WxyDLe12cdqzEvpR6jf3NbxiNysOCxwG4ErhaZGP+krcoB
    ObuL0nvls/+3myy5reKEyy22+0GvTDjaChfr+FwJjXMG+IBCLscYdgZC1LQL6oAn
    9xY5DH3W7BW4wR5ttxvtN32TkfVQh8xi3jrLrduUh+hV8DTiAiLIhv0Vykwhep2p
    WZA+7qbrYaYM8GLLgLrb6LfBoxeNxAEKiTpl1quFkm+Hk1dKq0EhVnxHf92x0zVF
    jRGZxAMNcrlCoE4f5XK45epVZSZvihdo1k73GPbp84aZ5P/xlO4OwZ3i4uCQXynl
    jE9c+I+4rRWKyPz9gkkqo0+teJL8ifeKt/3ab6FcdA0aArynqmsKJMktxmNu83We
    YVGEHZPeOlyOQqPvZqWsLnXQUfg54OkbuV4/4mWSIzxFXdFy/AekSeJugpswMXqn
    oNck4qySNyfnlyelppXyWWwDfVus9CVAGZmJQaJExHMT/rQFRVchlmY0Ddr5O264
    gcjv90o1NBOc2fNcqjivuoX7ROqys4K/YdNQ1HhQ7usJghADNOtuLI8ZqMh9akXD
    Eqp6Ne97wq1NiJj0nt3SJlzTnOyTjzrTe0Y+atPkVKp7SsjkATMI9JdhXwGhWd7a
    qFVl0owZiDasgEhyG2K5L6r+yaJLYkPVXZYC/wtWC3NEchnDWZGQcXzB4xROCQkD
    OlWNYDkPiZioeFkA3/fTMvG4moB2Pp9Q4GU5fJ6k43Ccu1up8dX/LumZb4ecg5/x
    -----END RSA PRIVATE KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem, "abcdef")
    assert_same_rsa rsa1024, key
    key = OpenSSL::PKey::RSA.new(pem) { "abcdef" }
    assert_same_rsa rsa1024, key

    cipher = OpenSSL::Cipher.new("aes-128-cbc")
    exported = rsa1024.to_pem(cipher, "abcdef\0\1")
    assert_same_rsa rsa1024, OpenSSL::PKey::RSA.new(exported, "abcdef\0\1")
    assert_raise(OpenSSL::PKey::RSAError) {
      OpenSSL::PKey::RSA.new(exported, "abcdef")
    }
  end

  def test_RSAPublicKey
    rsa1024 = Fixtures.pkey("rsa1024")
    rsa1024pub = OpenSSL::PKey::RSA.new(rsa1024.public_to_der)

    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(rsa1024.n),
      OpenSSL::ASN1::Integer(rsa1024.e)
    ])
    key = OpenSSL::PKey::RSA.new(asn1.to_der)
    assert_not_predicate key, :private?
    assert_same_rsa rsa1024pub, key

    pem = <<~EOF
    -----BEGIN RSA PUBLIC KEY-----
    MIGJAoGBAMvCxLDUQKc+1P4+Q6AeFwYDvWfALb+cvzlUEadGoPE6qNWHsLFoo8RF
    geyTgE8KQTduu1OE9Zz2SMcRBDu5/1jWtsLPSVrI2ofLLBARUsWanVyki39DeB4u
    /xkP2mKGjAokPIwOI3oCthSZlzO9bj3voxTf6XngTqUX8l8URTmHAgMBAAE=
    -----END RSA PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem)
    assert_same_rsa rsa1024pub, key
  end

  def test_PUBKEY
    rsa1024 = Fixtures.pkey("rsa1024")
    rsa1024pub = OpenSSL::PKey::RSA.new(rsa1024.public_to_der)

    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::ObjectId("rsaEncryption"),
        OpenSSL::ASN1::Null(nil)
      ]),
      OpenSSL::ASN1::BitString(
        OpenSSL::ASN1::Sequence([
          OpenSSL::ASN1::Integer(rsa1024.n),
          OpenSSL::ASN1::Integer(rsa1024.e)
        ]).to_der
      )
    ])
    key = OpenSSL::PKey::RSA.new(asn1.to_der)
    assert_not_predicate key, :private?
    assert_same_rsa rsa1024pub, key

    pem = <<~EOF
    -----BEGIN PUBLIC KEY-----
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLwsSw1ECnPtT+PkOgHhcGA71n
    wC2/nL85VBGnRqDxOqjVh7CxaKPERYHsk4BPCkE3brtThPWc9kjHEQQ7uf9Y1rbC
    z0layNqHyywQEVLFmp1cpIt/Q3geLv8ZD9pihowKJDyMDiN6ArYUmZczvW4976MU
    3+l54E6lF/JfFEU5hwIDAQAB
    -----END PUBLIC KEY-----
    EOF
    key = OpenSSL::PKey::RSA.new(pem)
    assert_same_rsa rsa1024pub, key

    assert_equal asn1.to_der, key.to_der
    assert_equal pem, key.export

    assert_equal asn1.to_der, rsa1024.public_to_der
    assert_equal asn1.to_der, key.public_to_der
    assert_equal pem, rsa1024.public_to_pem
    assert_equal pem, key.public_to_pem
  end

  def test_pem_passwd
    omit_on_fips

    key = Fixtures.pkey("rsa1024")
    pem3c = key.to_pem("aes-128-cbc", "key")
    assert_match (/ENCRYPTED/), pem3c
    assert_equal key.to_der, OpenSSL::PKey.read(pem3c, "key").to_der
    assert_equal key.to_der, OpenSSL::PKey.read(pem3c) { "key" }.to_der
    assert_raise(OpenSSL::PKey::PKeyError) {
      OpenSSL::PKey.read(pem3c) { nil }
    }
  end

  def test_private_encoding
    rsa1024 = Fixtures.pkey("rsa1024")
    asn1 = OpenSSL::ASN1::Sequence([
      OpenSSL::ASN1::Integer(0),
      OpenSSL::ASN1::Sequence([
        OpenSSL::ASN1::ObjectId("rsaEncryption"),
        OpenSSL::ASN1::Null(nil)
      ]),
      OpenSSL::ASN1::OctetString(rsa1024.to_der)
    ])
    assert_equal asn1.to_der, rsa1024.private_to_der
    assert_same_rsa rsa1024, OpenSSL::PKey.read(asn1.to_der)

    pem = <<~EOF
    -----BEGIN PRIVATE KEY-----
    MIICeAIBADANBgkqhkiG9w0BAQEFAASCAmIwggJeAgEAAoGBAMvCxLDUQKc+1P4+
    Q6AeFwYDvWfALb+cvzlUEadGoPE6qNWHsLFoo8RFgeyTgE8KQTduu1OE9Zz2SMcR
    BDu5/1jWtsLPSVrI2ofLLBARUsWanVyki39DeB4u/xkP2mKGjAokPIwOI3oCthSZ
    lzO9bj3voxTf6XngTqUX8l8URTmHAgMBAAECgYEApKX8xBqvJ7XI7Kypfo/x8MVC
    3rxW+1eQ2aVKIo4a7PKGjQz5RVIVyzqTUvSZoMTbkAxlSIbO5YfJpTnl3tFcOB6y
    QMxqQPW/pl6Ni3EmRJdsRM5MsPBRZOfrXxOCdvXu1TWOS1S1TrvEr/TyL9eh2WCd
    CGzpWgdO4KHce7vs7pECQQDv6DGoG5lHnvbvj9qSJb9K5ebRJc8S+LI7Uy5JHC0j
    zsHTYPSqBXwPVQdGbgCEycnwwKzXzT2QxAQmJBQKun2ZAkEA2W3aeAE7Xi6zo2eG
    4Cx4UNMHMIdfBRS7VgoekwybGmcapqV0aBew5kHeWAmxP1WUZ/dgZh2QtM1VuiBA
    qUqkHwJBAOJLCRvi/JB8N7z82lTk2i3R8gjyOwNQJv6ilZRMyZ9vFZFHcUE27zCf
    Kb+bX03h8WPwupjMdfgpjShU+7qq8nECQQDBrmyc16QVyo40sgTgblyiysitvviy
    ovwZsZv4q5MCmvOPnPUrwGbRRb2VONUOMOKpFiBl9lIv7HU//nj7FMVLAkBjUXED
    83dA8JcKM+HlioXEAxCzZVVhN+D63QwRwkN08xAPklfqDkcqccWDaZm2hdCtaYlK
    funwYkrzI1OikQSs
    -----END PRIVATE KEY-----
    EOF
    assert_equal pem, rsa1024.private_to_pem
    assert_same_rsa rsa1024, OpenSSL::PKey.read(pem)
  end

  def test_private_encoding_encrypted
    rsa = Fixtures.pkey("rsa2048")
    encoded = rsa.private_to_der("aes-128-cbc", "abcdef")
    asn1 = OpenSSL::ASN1.decode(encoded) # PKCS #8 EncryptedPrivateKeyInfo
    assert_kind_of OpenSSL::ASN1::Sequence, asn1
    assert_equal 2, asn1.value.size
    assert_not_equal rsa.private_to_der, encoded
    assert_same_rsa rsa, OpenSSL::PKey.read(encoded, "abcdef")
    assert_same_rsa rsa, OpenSSL::PKey.read(encoded) { "abcdef" }
    assert_raise(OpenSSL::PKey::PKeyError) { OpenSSL::PKey.read(encoded, "abcxyz") }

    encoded = rsa.private_to_pem("aes-128-cbc", "abcdef")
    assert_match (/BEGIN ENCRYPTED PRIVATE KEY/), encoded.lines[0]
    assert_same_rsa rsa, OpenSSL::PKey.read(encoded, "abcdef")

    # Use openssl instead of certtool due to https://gitlab.com/gnutls/gnutls/-/issues/1632
    # openssl pkcs8 -in test/openssl/fixtures/pkey/rsa2048.pem -topk8 -v2 aes-128-cbc -passout pass:abcdef
    pem = <<~EOF
    -----BEGIN ENCRYPTED PRIVATE KEY-----
    MIIFLTBXBgkqhkiG9w0BBQ0wSjApBgkqhkiG9w0BBQwwHAQIay5V8CDQi5oCAggA
    MAwGCCqGSIb3DQIJBQAwHQYJYIZIAWUDBAECBBB6eyagcbsvdQlM1kPcH7kiBIIE
    0Ng1apIyoPAZ4BfC4kMNeSmeAv3XspxqYi3uWzXiNyTcoE6390swrwM6WvdpXvLI
    /n/V06krxPZ9X4fBG2kLUzXt5f09lEvmQU1HW1wJGU5Sq3bNeXBrlJF4DzJE4WWd
    whVVvNMm44ghdzN/jGSw3z+6d717N+waa7vrpBDsHjhsPNwxpyzUvcFPFysTazxx
    kN/dziIBF6SRKi6w8VaJEMQ8czGu5T3jOc2e/1p3/AYhHLPS4NHhLR5OUh0TKqLK
    tANAqI9YqCAjhqcYCmN3mMQXY52VfOqG9hlX1x9ZQyqiH7l102EWbPqouk6bCBLQ
    wHepPg4uK99Wsdh65qEryNnXQ5ZmO6aGb6T3TFENCaNKmi8Nh+/5dr7J7YfhIwpo
    FqHvk0hrZ8r3EQlr8/td0Yb1/IKzeQ34638uXf9UxK7C6o+ilsmJDR4PHJUfZL23
    Yb9qWJ0GEzd5AMsI7x6KuUxSuH9nKniv5Tzyty3Xmb4FwXUyADWE19cVuaT+HrFz
    GraKnA3UXbEgWAU48/l4K2HcAHyHDD2Kbp8k+o1zUkH0fWUdfE6OUGtx19Fv44Jh
    B7xDngK8K48C6nrj06/DSYfXlb2X7WQiapeG4jt6U57tLH2XAjHCkvu0IBZ+//+P
    yIWduEHQ3w8FBRcIsTNJo5CjkGk580TVQB/OBLWfX48Ay3oF9zgnomDIlVjl9D0n
    lKxw/KMCLkvB78rUeGbr1Kwj36FhGpTBw3FgcYGa5oWFZTlcOgMTXLqlbb9JnDlA
    Zs7Tu0WTyOTV/Dne9nEm39Dzu6wRojiIpmygTD4FI7rmOy3CYNvL3XPv7XQj0hny
    Ee/fLxugYlQnwPZSqOVEQY2HsG7AmEHRsvy4bIWIGt+yzAPZixt9MUdJh91ttRt7
    QA/8J1pAsGqEuQpF6UUINZop3J7twfhO4zWYN/NNQ52eWNX2KLfjfGRhrvatzmZ0
    BuCsCI9hwEeE6PTlhbX1Rs177MrDc3vlqz2V3Po0OrFjXAyg9DR/OC4iK5wOG2ZD
    7StVSP8bzwQXsz3fJ0ardKXgnU2YDAP6Vykjgt+nFI09HV/S2faOc2g/UK4Y2khl
    J93u/GHMz/Kr3bKWGY1/6nPdIdFheQjsiNhd5gI4tWik2B3QwU9mETToZ2LSvDHU
    jYCys576xJLkdMM6nJdq72z4tCoES9IxyHVs4uLjHKIo/ZtKr+8xDo8IL4ax3U8+
    NMhs/lwReHmPGahm1fu9zLRbNCVL7e0zrOqbjvKcSEftObpV/LLcPYXtEm+lZcck
    /PMw49HSE364anKEXCH1cyVWJwdZRpFUHvRpLIrpHru7/cthhiEMdLgK1/x8sLob
    DiyieLxH1DPeXT4X+z94ER4IuPVOcV5AXc/omghispEX6DNUnn5jC4e3WyabjUbw
    MuO9lVH9Wi2/ynExCqVmQkdbTXuLwjni1fJ27Q5zb0aCmhO8eq6P869NCjhJuiUj
    NI9XtGLP50YVWE0kL8KEJqnyFudky8Khzk4/dyixQFqin5GfT4vetrLunGHy7lRB
    3LpnFrpMOr+0xr1RW1k9vlmjRsJSiojJfReYO7gH3B5swiww2azogoL+4jhF1Jxh
    OYLWdkKhP2jSVGqtIDtny0O4lBm2+hLpWjiI0mJQ7wdA
    -----END ENCRYPTED PRIVATE KEY-----
    EOF
    assert_same_rsa rsa, OpenSSL::PKey.read(pem, "abcdef")
  end

  def test_params
    key = Fixtures.pkey("rsa2048")
    assert_equal(2048, key.n.num_bits)
    assert_equal(key.n, key.params["n"])
    assert_equal(65537, key.e)
    assert_equal(key.e, key.params["e"])
    [:d, :p, :q, :dmp1, :dmq1, :iqmp].each do |name|
      assert_kind_of(OpenSSL::BN, key.send(name))
      assert_equal(key.send(name), key.params[name.to_s])
    end

    pubkey = OpenSSL::PKey.read(key.public_to_der)
    assert_equal(key.n, pubkey.n)
    assert_equal(key.e, pubkey.e)
    [:d, :p, :q, :dmp1, :dmq1, :iqmp].each do |name|
      assert_nil(pubkey.send(name))
      assert_equal(0, pubkey.params[name.to_s])
    end
  end

  def test_dup
    key = Fixtures.pkey("rsa1024")
    key2 = key.dup
    assert_equal key.params, key2.params

    # PKey is immutable in OpenSSL >= 3.0
    if !openssl?(3, 0, 0)
      key2.set_key(key2.n, 3, key2.d)
      assert_not_equal key.params, key2.params
    end
  end

  def test_marshal
    key = Fixtures.pkey("rsa2048")
    deserialized = Marshal.load(Marshal.dump(key))

    assert_equal key.to_der, deserialized.to_der
  end

  private
  def assert_same_rsa(expected, key)
    check_component(expected, key, [:n, :e, :d, :p, :q, :dmp1, :dmq1, :iqmp])
  end
end

end
