# Load the rails application.
require File.expand_path('../application', __FILE__)

# Initialize the rails application.
Buscador::Application.initialize!

ActiveSupport::Inflector.inflections do |inflect|
  inflect.plural /([aeiou])([A-Z]|_|$)/, '\1s\2'
  inflect.plural /([rlnd])([A-Z]|_|$)/, '\1es\2'
  inflect.plural /([aeiou])([A-Z]|_|$)([a-z]+)([rlnd])($)/, '\1s\2\3\4es\5'
  inflect.plural /([rlnd])([A-Z]|_|$)([a-z]+)([aeiou])($)/, '\1es\2\3\4s\5'
  inflect.singular /([aeiou])s([A-Z]|_|$)/, '\1\2'
  inflect.singular /([rlnd])es([A-Z]|_|$)/, '\1\2'
  inflect.singular /([aeiou])s([A-Z]|_)([a-z]+)([rlnd])es($)/, '\1\2\3\4\5'
  inflect.singular /([rlnd])es([A-Z]|_)([a-z]+)([aeiou])s($)/, '\1\2\3\4\5'
  inflect.irregular 'especy', 'especies'
end

ActionMailer::Base.smtp_settings = {
    :domain => CONFIG.smtp.domain,
    :address => CONFIG.smtp.address,
    #:user_name => CONFIG.smtp.user_name,
    #:password => CONFIG.smtp.password,
    #:port => CONFIG.smtp.port,
    :authentication => :plain,
    :enable_starttls_auto => true
}
