##
# PowerDNS Zone
#
module Pdns::Dns
  class Zone

    attr_accessor :id,
                  :name,
                  :records,
                  :dnssec,
                  :account_id,
                  :features,
                  :soa_email,
                  :axfr_ips,
                  :errors,
                  :updated_at,
                  :created_at

    # Re-attach a client after Marshal.load (the controller stores zones without one).
    attr_writer :client

    MISSING_CLIENT_MESSAGE = 'zone has no client; set Zone#client= after Marshal.load'.freeze

    def initialize(client, id, data = {})
      @client = client
      self.errors = []
      self.axfr_ips = []
      self.records = default_records
      self.id = id
      self.name = data['name'] if data['name']
      if data.empty?
        self.dnssec = false
        self.features = {}
      else
        self.dnssec = data['dnssec']
        self.features = {
          'account' => data['account'],
          'kind' => data['kind'],
          'masters' => data['masters']
        }
      end
      load!(data) unless id.nil?
    end

    def load!(data)
      self.dnssec = data['dnssec']
      self.records = process_records!(data) unless data['rrsets'].nil?
    end

    # def zone
    #   # ?
    # end

    def enable_dnssec!; end

    # View DNSec Params
    def sec_params
      return nil unless self.dnssec
      require_client!
      response = @client.exec!('get', "zones/#{self.id}/cryptokeys")
      result = []
      response.each do |ds|
        keys = []
        # PowerDNS only returns 'ds' for KSK/CSK keys.
        Array(ds['ds']).each do |i|
          k = i.split(' ')
          dtype = case k[2].to_i
            when 1
              'sha1'
            when 2
              'sha256'
            when 3
              'gost r 34.11-94'
            when 4
              'sha384'
            else
              'unknown'
          end
          keys << {
            'tag' => k[0],
            'algo' => k[1],
            'digest_type' => k[2],
            'digest_type_human' => dtype,
            'digest' => k[3]
          }
        end
        result << {
          'id' => ds['id'],
          'tag' => keys.first&.fetch('tag'),
          'algo' => keys.first&.fetch('algo'),
          'active' => ds['active'],
          'flags' => ds['flags'],
          'keytype' => ds['keytype'],
          'type' => ds['type'],
          'keys' => keys
        }
      end
      result
    end

    def save
      if self.id.nil?
        create!
        return Pdns::Dns::Zone.find(@client, self.id) if self.errors.empty?
        false # Because we failed to create it!
      else
        update!
      end
    end

    def update!
      require_client!
      update_data = {'rrsets' => []}
      current_records = ungrouped_records
      # Load /current/ data to compare
      existing_data = @client.exec!('get', "zones/#{self.id}")
      existing_data['rrsets'].each do |rset|
        local = current_records.select { |i| i.type == rset['type'] && i.name == rset['name'] }
        if local.empty?
          update_data['rrsets'] << {
            'name' => rset['name'],
            'type' => rset['type'],
            'changetype' => 'DELETE'
          }
        else
          server_ttl = rset['ttl']
          ttl = local.map { |i| coerce_ttl(i.ttl) }.find { |t| !t.nil? && t != server_ttl }
          update_data['rrsets'] << {
            'name' => rset['name'],
            'type' => rset['type'],
            'ttl' => ttl || coerce_ttl(server_ttl) || 3600,
            'changetype' => 'REPLACE',
            'records' => local.map { |i| record_payload(i, rset['records']) }
          }
        end
      end # End existing_data['rrsets'].each
      # Look for new record sets (unique name/type pairs, first-seen order)
      new_records = []
      current_records.each do |i|
        key = [i.name, i.type]
        next if new_records.include?(key)
        next if update_data['rrsets'].any? { |ii| ii['name'] == i.name && ii['type'] == i.type }
        new_records << key
      end
      new_records.each do |record, type|
        local = current_records.select { |i| i.type == type && i.name == record }
        next if local.empty?
        ttl = local.map { |i| coerce_ttl(i.ttl) }.compact.first
        update_data['rrsets'] << {
          'name' => record,
          'type' => type,
          'ttl' => ttl || 3600,
          'changetype' => 'REPLACE',
          'records' => local.map { |i| record_payload(i, nil) }
        }
      end
      @client.exec!('put', "zones/#{self.id}", update_data)
    end

    def create!
      require_client!
      self.name = self.name.strip
      self.name = "#{self.name}." unless self.name.end_with?('.')
      self.id = self.name
      data = {
        'name' => self.name,
        'kind' => Pdns.config[:zone_type] == 'Native' ? 'Native' : 'Master',
        'masters' => Pdns.config[:masters],
        'nameservers' => Pdns.config[:nameservers]
      }
      @client.exec!('post', 'zones', data)
      
      ##
      # Possible use-case for the future, but right now we're useing `allow-axfr-ips` in the master config.
      #
      # Set MetaData to allow AXFR to Slaves
      # https://doc.powerdns.com/md/httpapi/api_spec/#zone-metadata
      # if Pdns.config[:zone_type] == 'Master' && @client.api_version > 4.0 # Currently expected to be supported in v4.1x
      #   metadata = {
      #     'type' => "Metadata",
      #     'kind' => "ALLOW-AXFR-FROM",
      #     'metadata' => ["AUTO-NS"]
      #   }
      #   @client.exec!('post', "zones/#{self.id}/metadata", metadata)
      # end
    end

    def destroy
      require_client!
      @client.exec!('delete', "zones/#{self.id}")
    rescue => e
      self.errors << e.inspect.to_s
      false
    else
      true
    end

    class << self

      def list_all_zones(client)
        zones_raw = client.exec!('get', 'zones')
        zones = []
        zones_raw.each do |zone|
          zones << Pdns::Dns::Zone.new(client, zone['id'], zone)
        end
        zones
      end

      def find(client, zone_name)
        data = client.exec!('get', "zones/#{zone_name}")
        Pdns::Dns::Zone.new(client, zone_name, data)
      rescue Pdns::UnknownObject
        nil
      end

    end

    private

    def require_client!
      raise Pdns::MissingParameter, MISSING_CLIENT_MESSAGE if @client.nil?
    end

    # Convert 'process_records' to just an array of records
    def ungrouped_records
      self.records.values.flatten
    end

    # Integer TTL from an Integer or a base-10 String; nil otherwise.
    def coerce_ttl(ttl)
      case ttl
      when Integer
        ttl
      when String
        str = ttl.strip
        return nil if str.empty?
        Integer(str, 10)
      end
    rescue ArgumentError
      nil
    end

    # PowerDNS record payload. 'disabled' is always a boolean: the record's own value when set,
    # otherwise that of the server record with identical content (old dumps and controller-built
    # records have no @disabled), otherwise false.
    def record_payload(record, server_records)
      content = record.raw_value
      disabled = record.disabled
      if disabled.nil?
        match = Array(server_records).find { |r| r['content'] == content }
        disabled = match ? match['disabled'] : false
      end
      {'content' => content, 'disabled' => disabled == true}
    end

    # Take records and place them into groups for easy rendering client side.
    def process_records!(data)
      records = default_records
      data['rrsets'].each do |i|
        type = i['type']
        ttl = i['ttl']
        name = i['name']
        i['records'].each do |ii|
          record_data = {
            'name' => name,
            'type' => type,
            'ttl' => ttl,
            'content' => ii['content'],
            'disabled' => ii['disabled']
          }
          records[type] = [] if records[type].nil?
          records[type] << Pdns::Dns::ZoneRecord.new(nil, nil, nil, record_data)
        end
      end
      self.records = records
    end

    def default_records
      {
          'A' => [],
          'AAAA' => [],
          'CAA' => [],
          'CNAME' => [],
          'DS' => [],
          'HINFO' => [],
          'MX' => [],
          'NAPTR' => [],
          'NS' => [],
          'PTR' => [],
          'SRV' => [],
          'SOA' => [],
          'SSHFP' => [],
          'TLSA' => [],
          'TXT' => []
      }
    end

  end
end
