module Admin
  class BooksController < Admin::ApplicationController
    # Kicks off the full AI flow in the background (grounded metadata judging
    # + cover swap) and returns immediately — the run typically takes a
    # couple of minutes because of multiple gateway calls and vision checks.
    def enrich
      book = find_resource(params[:id])

      if ENV["OTARI_API_KEY"].blank?
        return redirect_to admin_book_path(book),
          alert: "Otari is not configured — set OTARI_BASE_URL and OTARI_API_KEY."
      end

      begin
        BookEnrichmentJob.perform_later(book.id)
      rescue StandardError => e
        return redirect_to admin_book_path(book),
          alert: "Enrichment failed: #{e.message}"
      end
      redirect_to admin_book_path(book),
        notice: "AI enrichment queued for “#{book.title}” — it runs in the background (usually 1–2 minutes). Refresh this page to see the audit panel update."
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
