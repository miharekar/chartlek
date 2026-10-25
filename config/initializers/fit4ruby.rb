require "fit4ruby"

Fit4Ruby::Log.level = Logger::FATAL
Fit4Ruby::Activity.class_eval { def check; end }
