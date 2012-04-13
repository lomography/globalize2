module Globalize
  module ActiveRecord
    class Adapter
      # The cache caches attributes that already were looked up for read access.
      # The stash keeps track of new or changed values that need to be saved.
      attr_reader :record, :cache, :stash

      def initialize(record)
        @record = record
        @cache = Attributes.new
        @stash = Attributes.new
      end

      def fetch(locale, attr_name)
        if cache.contains?(locale, attr_name)
          cache.read(locale, attr_name)
        else
          if block_given?
            cache.write(locale, attr_name, fetch_attribute(locale, attr_name) {yield})
          else
            cache.write(locale, attr_name, fetch_attribute(locale, attr_name))
          end

        end
      end

      def write(locale, attr_name, value)
        stash.write(locale, attr_name, value)
        cache.write(locale, attr_name, value)
      end

      def save_translations!
        stash.each do |locale, attrs|
          translation = record.translations.find_or_initialize_by_locale(locale.to_s)
          attrs.each { |attr_name, value| translation[attr_name] = value }
          translation.save!
        end
        stash.clear
      end

      def reset
        cache.clear
        # stash.clear
      end

      protected

        def fetch_translation(locale)
          locale = locale.to_sym
          if block_given?
            record.translations.detect { |t| t.locale == locale && t.visible == yield[:visible]} if(record.translations.loaded?)
            record.translations.by_locale(locale){yield} unless(record.translations.loaded?)
          else
            record.translations.detect { |t| t.locale == locale} if(record.translations.loaded?)
            record.translations.by_locale(locale) unless(record.translations.loaded?)
          end
        end

        def fetch_translations(locale)
          # only query if not already included with :include => translations
          if block_given?
            record.translations.collect{ |t| t if(t.visible == yield[:visible])}.uniq.delete_if{|t| t.nil?} if(record.translations.loaded?)
            record.translations.by_locales(Globalize.fallbacks(locale)){yield} unless(record.translations.loaded?)
          else
            record.translations if(record.translations.loaded?)
            record.translations.by_locales(Globalize.fallbacks(locale)) unless(record.translations.loaded?)
          end
        end

        def fetch_attribute(locale, attr_name)
          if block_given?
            translations = fetch_translations(locale) {yield}
            # to have some translations for fallback
            translations = fetch_translations(locale) { {:visible => true } } if translations.empty?
          else
            translations = fetch_translations(locale)
          end
          value, requested_locale = nil, locale

          Globalize.fallbacks(locale).each do |fallback|
            translation = translations.detect { |t|
              t.locale == fallback
            }
            value  = translation && translation.send(attr_name)
            locale = fallback && break if value
          end

          set_metadata(value, :locale => locale, :requested_locale => requested_locale)
          value
        end

        def set_metadata(object, metadata)
          if object.respond_to?(:translation_metadata)
            object.translation_metadata.merge!(meta_data)
          end
        end

        def translation_metadata_accessor(object)
          return if obj.respond_to?(:translation_metadata)
          class << object; attr_accessor :translation_metadata end
          object.translation_metadata ||= {}
        end
    end
  end
end
