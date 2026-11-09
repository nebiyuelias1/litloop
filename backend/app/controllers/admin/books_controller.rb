module Admin
  class BooksController < Admin::ApplicationController
    # Runs the Otari AI enrichment synchronously so the admin can see the
    # result immediately: metadata (description, tags, country) first, then
    # the cover image where a better one can be verified.
    def enrich
      book = find_resource(params[:id])

      if ENV["OTARI_API_KEY"].blank?
        return redirect_to admin_book_path(book),
          alert: "Otari is not configured — set OTARI_BASE_URL and OTARI_API_KEY."
      end

      result = BookMetadataEnricher.new(book: book).enrich!

      # The judge decides whether the current cover is missing/low quality;
      # the improver only runs when the judgment calls for a replacement.
      if %w[missing low_quality].include?(result.cover_judgment.to_s)
        cover = BookCoverImprover.new(book: book).improve!
        cover_note = cover.improved ? "cover ⬆ #{URI.parse(cover.new_cover).host} (#{cover.reason})" : "cover: needed, but no candidate verified (#{cover.reason})"
      else
        cover_note = "cover #{result.cover_judgment || 'n/a'} (kept)"
      end

      notice = "Enriched “#{book.title}”: tags=[#{result.tags_added.join(', ')}] " \
        "country=#{result.country_of_origin || 'n/a'}" +
        (result.country_source.present? ? " (source: #{result.country_source})" : "") +
        "; #{cover_note}"
      redirect_to admin_book_path(book), notice: notice
    rescue OtariClient::RequestError, OtariClient::ConfigurationError => e
      redirect_to admin_book_path(book), alert: "Enrichment failed: #{e.message}"
    end
    # Overwrite any of the RESTful controller actions to implement custom behavior
    # For example, you may want to send an email after a foo is updated.
    #
    # def update
    #   super
    #   send_foo_updated_email(requested_resource)
    # end

    # Override this method to specify custom lookup behavior.
    # This will be used to set the resource for the `show`, `edit`, and `update`
    # actions.
    #
    # def find_resource(param)
    #   Foo.find_by!(slug: param)
    # end

    # The result of this lookup will be available as `requested_resource`

    # Override this if you have certain roles that require a subset
    # this will be used to set the records shown on the `index` action.
    #
    # def scoped_resource
    #   if current_user.super_admin?
    #     resource_class
    #   else
    #     resource_class.with_less_stuff
    #   end
    # end

    # Override `resource_params` if you want to transform the submitted
    # data before it's persisted. For example, the following would turn all
    # empty values into nil values. It uses other APIs such as `resource_class`
    # and `dashboard`:
    #
    # def resource_params
    #   params.require(resource_class.model_name.param_key).
    #     permit(dashboard.permitted_attributes(action_name)).
    #     transform_values { |value| value == "" ? nil : value }
    # end

    # See https://administrate-demo.herokuapp.com/customizing_controller_actions
    # for more information
  end
end
