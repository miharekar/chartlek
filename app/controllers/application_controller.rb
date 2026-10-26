class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :sync_profile, :current_theme

  private
  def current_theme
    cookies[:theme].presence_in(ThemesController::THEMES) || "system"
  end

  def sync_profile
    @sync_profile ||= Profile.instance
  end
end
