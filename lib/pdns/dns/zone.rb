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
                  :updated_at,
                  :created_at

    def initialize(client, id, data = {})
      @client = client
      if self.id
        self.id = "#{self.id}." if self.id.strip.split('').last != '.'
      else
        self.id = nil
        self.name = nil
      end
      self.id = id
      self.records = []
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
      data = data.empty? ? @client.exec!('get', "zones/#{self.id}") : data
      data['rrsets'].each do |i|
        type = i['type']
        ttl = i['ttl']
        name = i['name']
        i['records'].each do |ii|
          record_data = {
            'name' => name,
            'type' => type,
            'ttl' => ttl,
            'content' => ii['content']
          }
          self.records << Pdns::Dns::ZoneRecord.new(nil, nil, nil, record_data)
        end
      end
    end

    def zone
      # ?
    end

    def save
      self.id.nil? ? create! : update!
    end

    def update!
      update_data = {'rrsets' => []}
      # Load /current/ data to compare
      existing_data = @client.exec!('get', "zones/#{self.id}")
      existing_data['rrsets'].each do |rset|
        update_record = {
          'name' => rset['name'],
          'type' => rset['type'],
          'ttl' => rset['ttl'],
          'changetype' => 'REPLACE',
          'records' => []
        }
        self.records.each do |i|
          if i.type == rset['type'] && i.name == rset['name']
            update_record['ttl'] = i.ttl
            update_record['records'] << {'content' => i.raw_value, 'disabled' => false}
          end
        end
        if update_record['records'].empty?
          update_data['rrsets'] << {
            'name' => rset['name'],
            'type' => rset['type'],
            'changetype' => 'DELETE'
          }
        else
          update_data['rrsets'] << update_record
        end
      end # End existing_data['rrsets'].each
      # Look for new record sets
      new_records = []
      self.records.each do |i|
        is_new = true
        update_data['rrsets'].each do |ii|
          if ii['name'] == i.name && ii['type'] == i.type
            is_new = false
          end
        end
        new_records << [i.name, i.type] if is_new
      end
      new_records.each do |record, type|
        update_record = {
          'name' => record,
          'type' => type,
          'ttl' => 3600,
          'changetype' => 'REPLACE',
          'records' => []
        }
        self.records.each do |i|
          if i.type == type && i.name == record
            update_record['ttl'] = i.ttl
            update_record['records'] << {'content' => i.raw_value, 'disabled' => false}
          end
        end
        unless update_record['records'].empty?
          update_data['rrsets'] << update_record
        end
      end
      @client.exec!('put', "zones/#{self.id}", update_data)
    end

    def create!
      if self.name.strip.split('').last != '.'
        self.name = "#{self.name}."
      end
      data = {
        'name' => self.name,
        'kind' => Pdns.config[:zone_type] == 'Native' ? 'Native' : 'Master',
        'masters' => Pdns.config[:masters],
        'nameservers' => Pdns.config[:nameservers]
      }
      result = @client.exec!('post', 'zones', data)
      self.id = result['id']
      self.load!(result)
      true
    end

    def destroy
      begin
        @client.exec!('delete', "zones/#{self.id}")
      rescue
        false
      else
        true
      end
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

    end

  end
end
