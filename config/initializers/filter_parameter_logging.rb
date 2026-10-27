# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
  passw email secret token _key crypt salt certificate otp ssn cvv cvc code
]

Rails.application.config.filter_parameters += [
  :resting_hr, :hr_zones, :hrv_, :body_battery, :stress_avg, :weight_kg, :sleep_, /\Araw\z/
]
