# PowerDNS Client
#
module Pdns
  class Client

    attr_accessor :endpoint,
                  :auth,
                  :api_version

    def initialize(endpoint, auth, data = {})
      self.endpoint = endpoint
      self.auth = auth
      self.api_version = version
    end

    # TODO: Attempt to discover the API version, as this is how we determine if the API is availble.
    def version
      1
    end

    def exec!(http_method, path, data = {})
      basic_auth = {username: self.auth.username, password: self.auth.password}
      url_base = "#{self.endpoint}/#{path}"
      rsp_headers = { 'X-API-Key' => self.auth.api_key, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      opts = {:basic_auth => basic_auth, :timeout => 40, :headers => rsp_headers, verify: false}
      unless data.empty?
        data = data.to_json
      end
      response = case http_method
        when 'get'
          HTTParty.get(url_base, opts)
        when 'post'
          HTTParty.post(url_base, opts.merge!(body: data))
        when 'put'
          HTTParty.patch(url_base, opts.merge!(body: data))
        when 'delete'
          HTTParty.delete(url_base, opts)
      end
      acceptable_codes = [200,201,204]
      begin
        rsp_code = response.code
      rescue
        raise GeneralError, 'Fatal Error: Unable to retrieve HTTP Status code.'
      end
      if rsp_code == 404
        raise UnknownObject
      elsif rsp_code == 401
        raise AuthenticationFailed, 'Invalid Login Credentials.'
      elsif !acceptable_codes.include?(rsp_code)
        raise GeneralError, response.body
      end
      response
    end

  end
end
