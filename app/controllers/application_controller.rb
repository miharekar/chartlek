class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :sync_if_due, if: -> { request.get? && request.format.html? }

  helper_method :sync_profile

  private
  def sync_profile
    @sync_profile ||= Profile.instance
  end

  def sync_if_due
    Activity.sync_later if sync_profile.sync_due?
  end
end
