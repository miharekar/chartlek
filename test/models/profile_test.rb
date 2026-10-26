require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  setup { @profile = Profile.instance }

  test "instance is a singleton" do
    assert_equal @profile, Profile.instance
    assert_equal 1, Profile.count
  end

  test "start_sync claims once" do
    assert @profile.start_sync
    assert @profile.syncing?
    assert_not Profile.instance.start_sync
  end

  test "sync_progress refreshes the running state" do
    @profile.start_sync
    travel 14.minutes

    @profile.sync_progress
    travel 14.minutes

    assert Profile.instance.syncing?
    travel_back
  end

  test "start_sync takes over a stale sync and clears the error" do
    @profile.update!(sync_started_at: 16.minutes.ago, sync_error: "boom")

    assert @profile.start_sync
    assert_nil @profile.sync_error
    assert @profile.syncing?
  end

  test "start_sync notes whether the previous sync was interrupted" do
    @profile.start_sync
    assert_not @profile.resuming_sync?
    @profile.finish_sync

    @profile.start_sync
    assert_not @profile.resuming_sync?
    @profile.finish_sync(error: "boom")

    @profile.start_sync
    assert @profile.resuming_sync?
    @profile.update!(sync_started_at: 20.minutes.ago)

    @profile.start_sync
    assert @profile.resuming_sync?
    @profile.finish_sync

    @profile.start_sync
    assert_not @profile.resuming_sync?
  end

  test "finish_sync records success and failure" do
    @profile.start_sync
    @profile.finish_sync

    assert @profile.synced_at
    assert_not @profile.syncing?

    @profile.start_sync
    @profile.finish_sync(error: "boom")

    assert_equal "boom", @profile.sync_error
    assert_not @profile.syncing?
  end

  test "invalid_key?" do
    assert_not @profile.invalid_key?

    @profile.update!(sync_error: Profile::INVALID_KEY_ERROR)

    assert @profile.invalid_key?
  end
end
