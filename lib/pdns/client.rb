# PowerDNS Client
#
module Pdns
  class Client

    HTTP_METHODS = {
      'get' => :get,
      'post' => :post,
      'put' => :patch,
      'delete' => :delete
    }.freeze

    TIMEOUT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout].freeze

    CONNECTION_ERRORS = [
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::EHOSTUNREACH,
      Errno::ENETUNREACH,
      SocketError,
      OpenSSL::SSL::SSLError
    ].freeze

    attr_accessor :endpoint,
                  :auth

    attr_writer :api_version

    def initialize(endpoint, auth, data = {})
      self.endpoint = endpoint
      self.auth = auth
    end

    # Server version string, fetched from the API.
    def version
      exec!('get', Pdns.config[:server])['version']
    end

    def api_version
      @api_version ||= version
    end

    def exec!(http_method, path, data = {})
      verb = HTTP_METHODS[http_method]
      raise InvalidParameter, "Unknown HTTP method: #{http_method.inspect}" if verb.nil?

      base = base_url
      url = "#{base}/#{server_path(path)}"
      basic_auth = {username: self.auth.username, password: self.auth.password}
      rsp_headers = { 'X-API-Key' => self.auth.api_key, 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
      opts = {:basic_auth => basic_auth, :timeout => 40, :headers => rsp_headers, verify: false}
      if verb == :post || verb == :patch
        opts[:body] = data.empty? ? data : data.to_json
      end

      begin
        response = HTTParty.send(verb, url, opts)
      rescue *TIMEOUT_ERRORS => e
        raise ConnectionTimeout, "Timed out connecting to #{host_of(base)} (#{e.class})"
      rescue *CONNECTION_ERRORS => e
        raise ConnectionFailed, "Unable to connect to #{host_of(base)} (#{e.class})"
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

    private

    # Endpoint with any trailing "/" and "/<server>" removed, so both
    # ".../servers" and ".../servers/<server>" are accepted.
    def base_url
      base = self.endpoint.to_s
      base = base.delete_suffix('/')
      base.delete_suffix("/#{Pdns.config[:server]}")
    end

    def server_path(path)
      server = Pdns.config[:server]
      path = path.to_s
      return path if path == server || path.start_with?("#{server}/")
      "#{server}/#{path}"
    end

    def host_of(url)
      URI.parse(url).host || 'PowerDNS server'
    rescue URI::InvalidURIError
      'PowerDNS server'
    end

  end
end
