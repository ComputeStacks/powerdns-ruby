# PowerDNS Authentication Object
# (0, 'admin', 'webserver-password', 'api-key')
module Pdns
  class Auth

    attr_accessor :user_id,
                  :username,
                  :password,
                  :api_key

    def initialize(user_id, username, password, api_key)
      self.user_id = user_id
      self.username = username
      self.password = password
      self.api_key = api_key
    end

  end
end
