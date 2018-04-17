##
# Settings
#
module Pdns
  class Settings

    attr_accessor :key,
                  :value

    def initialize(val = {})
      val.each_key do |i|
        self.key = i
        self.value = val[i]
      end
    end

    class << self

      def host_settings(client = nil)
        {
          'dns' => true,
          'auth_type' => 'master' # Master account or user account.
        }
      end

      # List available features for each Module.
      def available_actions
        {
          'dns' => ['update_by_zone'] # Update the entire zone file rather than individual record_ids.
        }
      end

      # Do you need a SOA email?
      def require_email_on_create?
        false
      end

      # Allow viewing all zones on the DNS server, including those not
      # known to the application.
      #
      # This will also prevent adding zones that already exist on the DNS server.
      def allow_unknown_zones?
        true
      end

      # Allow listing all domains on a DNS server.
      def allow_list_all?
        true
      end

      # Support DNSSEC?
      def supports_dnssec?
        true
      end

    end
  end
end
