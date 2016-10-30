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

    end
  end
end
