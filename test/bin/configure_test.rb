require "test_helper"
require "tmpdir"
require "fileutils"
require "open3"
require "dotenv"

class ConfigureTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    FileUtils.mkdir(File.join(@dir, "bin"))
    FileUtils.cp Rails.root.join("bin/configure"), File.join(@dir, "bin/configure")
    FileUtils.cp Rails.root.join(".env.example"), @dir
  end

  teardown { FileUtils.remove_entry(@dir) }

  def configure
    out, status = Open3.capture2e({"PATH" => ENV["PATH"], "HOME" => @dir}, File.join(@dir, "bin/configure"), unsetenv_others: true)
    assert status.success?, out
    out
  end

  def env_path
    File.join(@dir, ".env")
  end

  def secret_line(lines)
    lines.grep(/\ASECRET_KEY_BASE=/).sole
  end

  test "a fresh directory gets a private .env with a generated secret and the template otherwise" do
    out = configure

    assert_equal 0o600, File.stat(env_path).mode & 0o777
    lines = File.readlines(env_path, chomp: true)
    assert_match(/\ASECRET_KEY_BASE=\h{128}\z/, secret_line(lines))
    assert_equal File.readlines(File.join(@dir, ".env.example"), chomp: true) - ["SECRET_KEY_BASE="], lines - [secret_line(lines)]
    assert_no_match(/\h{64}/, out)
    assert_empty Dir.children(@dir).grep(/configure\./)
  end

  test "a second run changes nothing" do
    configure
    before = File.binread(env_path)

    configure

    assert_equal before, File.binread(env_path)
  end

  test "an empty secret is filled in and every other line is kept" do
    File.write(env_path, "GARMIN_API_TOKEN=garmin-fake\nSECRET_KEY_BASE=\nMAPBOX_TOKEN=pk.fake\n")

    configure

    lines = File.readlines(env_path, chomp: true)
    assert_equal "GARMIN_API_TOKEN=garmin-fake", lines[0]
    assert_match(/\ASECRET_KEY_BASE=\h{128}\z/, lines[1])
    assert_equal "MAPBOX_TOKEN=pk.fake", lines[2]
    assert_equal 3, lines.size
    assert_no_match(/Garmin Personal API key/, configure)
  end

  test "blank-looking secrets are replaced in place, and dotenv reads the result" do
    ["SECRET_KEY_BASE=\"\"", "SECRET_KEY_BASE=''", "SECRET_KEY_BASE=   ", "SECRET_KEY_BASE=\" \"", "SECRET_KEY_BASE=\r"].each do |line|
      File.write(env_path, "GARMIN_API_TOKEN=garmin-fake\n#{line}\nMAPBOX_TOKEN=pk.fake\n")

      configure

      lines = File.readlines(env_path, chomp: true)
      assert_equal 3, lines.size, line
      assert_match(/\ASECRET_KEY_BASE=\h{128}\z/, lines[1], line)
      assert_match(/\A\h{128}\z/, Dotenv.parse(env_path, overwrite: true)["SECRET_KEY_BASE"], line)
    end
  end

  test "a CRLF file keeps its other lines and gets the secret in place" do
    File.binwrite(env_path, "GARMIN_API_TOKEN=garmin-fake\r\nSECRET_KEY_BASE=\r\nMAPBOX_TOKEN=pk.fake\r\n")

    configure

    parsed = Dotenv.parse(env_path, overwrite: true)
    assert_match(/\A\h{128}\z/, parsed["SECRET_KEY_BASE"])
    assert_equal "garmin-fake", parsed["GARMIN_API_TOKEN"]
    assert_equal "pk.fake", parsed["MAPBOX_TOKEN"]
    assert_equal 1, File.read(env_path).scan("SECRET_KEY_BASE=").size
  end

  test "a set secret behind export or indentation is kept and nothing is appended" do
    ["export SECRET_KEY_BASE=keep", "  SECRET_KEY_BASE=keep", "\texport  SECRET_KEY_BASE=keep"].each do |line|
      File.write(env_path, "GARMIN_API_TOKEN=garmin-fake\n#{line}\n")
      before = File.binread(env_path)

      configure

      assert_equal before, File.binread(env_path), line
      assert_equal "keep", Dotenv.parse(env_path, overwrite: true)["SECRET_KEY_BASE"], line
    end
  end

  test "a blank export line is replaced in place" do
    File.write(env_path, "GARMIN_API_TOKEN=garmin-fake\nexport SECRET_KEY_BASE=\nMAPBOX_TOKEN=pk.fake\n")

    configure

    lines = File.readlines(env_path, chomp: true)
    assert_equal 3, lines.size
    assert_match(/\ASECRET_KEY_BASE=\h{128}\z/, lines[1])
    assert_match(/\A\h{128}\z/, Dotenv.parse(env_path, overwrite: true)["SECRET_KEY_BASE"])
  end

  test "a set secret is kept" do
    File.write(env_path, "SECRET_KEY_BASE=keep-me\n")

    configure

    assert_equal "SECRET_KEY_BASE=keep-me\n", File.read(env_path)
  end

  test "a missing line is appended, even after a last line without a newline" do
    File.write(env_path, "GARMIN_API_TOKEN=garmin-fake")

    configure

    lines = File.readlines(env_path, chomp: true)
    assert_equal "GARMIN_API_TOKEN=garmin-fake", lines[0]
    assert_match(/\ASECRET_KEY_BASE=\h{128}\z/, lines[1])
    assert_equal 2, lines.size
  end

  test "the Garmin reminder shows while the key is empty" do
    assert_match(/GARMIN_API_TOKEN/, configure)
  end
end
