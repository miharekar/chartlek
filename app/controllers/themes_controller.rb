class ThemesController < ApplicationController
  THEMES = %w[system light dark].freeze

  def update
    cookies.permanent[:theme] = {value: params[:theme], httponly: true, same_site: :lax} if THEMES.include?(params[:theme])

    redirect_back_or_to root_path
  end
end
