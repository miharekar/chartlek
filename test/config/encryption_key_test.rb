require "test_helper"

class EncryptionKeyTest < ActiveSupport::TestCase
  SECRET = "test-secret-key-base-0123456789"

  def key(name, env)
    Chartlek::Application.encryption_key(name, env)
  end

  test "derives the keys from SECRET_KEY_BASE, pinned so an upgrade can't change them" do
    env = {"SECRET_KEY_BASE" => SECRET}

    assert_equal "bb3fe310cd582f3583fd15389c37862da6b3cea03193b3756f51694480b52bd3", key("primary_key", env)
    assert_equal "31c9666ebf9fe5642b0a1c2bf7698c0c9d729f312da40dcd80a9086bb4ab0555", key("deterministic_key", env)
    assert_equal "0eea37b818dc60fdcc88c7ff557bb2f34b735b0232702e1e72f4845fa090297a", key("key_derivation_salt", env)
  end

  test "a non-empty explicit value wins" do
    env = {"SECRET_KEY_BASE" => SECRET, "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "explicit"}

    assert_equal "explicit", key("primary_key", env)
    assert_not_equal "explicit", key("deterministic_key", env)
  end

  test "an empty explicit value counts as unset" do
    env = {"SECRET_KEY_BASE" => SECRET, "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => ""}

    assert_equal key("primary_key", {"SECRET_KEY_BASE" => SECRET}), key("primary_key", env)
  end

  test "there is no key without a secret" do
    assert_nil key("primary_key", {})
    assert_nil key("primary_key", {"SECRET_KEY_BASE" => "", "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => ""})
  end
end
