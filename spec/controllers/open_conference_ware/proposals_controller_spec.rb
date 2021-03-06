require 'spec_helper'

describe OpenConferenceWare::ProposalsController do
  render_views
  fixtures :all
  routes { OpenConferenceWare::Engine.routes }

  # Return an array of Proposal objects extracted from the response body.
  def extract_proposals
    return assert_select('.proposal_row').map{|n| Proposal.find(n.attributes['id'].gsub(/^proposal_row_/, ''))}
  end

  before do
    @event = events(:open)
  end

  describe "index" do
    describe "when returning HTML" do
      before do
        get :index, event_id: @event.slug
      end

      it "should be successful" do
        response.should be_success
      end

      it "should assign an event" do
        assigns(:event).should == @event
      end

      it "should assign proposals" do
        assigns(:proposals).should_not be_blank
      end
    end

    describe "when returning CSV" do

      def get_csv_index
        OpenConferenceWare.stub(have_user_profiles: true)
        OpenConferenceWare.stub(have_multiple_presenters: true)
        stub_current_event!(event: @event)

        get :index, event_id: @event.to_param, format: "csv"

        @rows = CSV.parse(response.body)
        @header = @rows.shift
      end

      shared_examples_for "shared CSV behaviors" do

        it "should return CSV" do
          @rows.should be_a_kind_of(Array)
        end

        it "should see public fields" do
          @header.should include("Title")
        end
      end

      shared_examples_for "shared non-admin CSV behaviors" do
        it "should not see private fields" do
          @header.should_not include("Emails")
        end
      end

      describe "anonymous user" do
        before do
          logout
        end

        describe "with visible schedule" do
          before do
            @controller.stub(:schedule_visible? => true)
            get_csv_index
          end

          it_should_behave_like "shared CSV behaviors"

          it_should_behave_like "shared non-admin CSV behaviors"

          it "should see schedule fields" do
            @header.should include("Start Time")
          end
        end

        describe "without visible schedule" do
          before do
            @controller.stub(:schedule_visible? => false)
            get_csv_index
          end

          it_should_behave_like "shared CSV behaviors"

          it_should_behave_like "shared non-admin CSV behaviors"

          it "should not see schedule fields" do
            @header.should_not include("Start Time")
          end
        end

      end

      describe "mortal user" do
        before do
          login_as(:quentin)
          get_csv_index
        end

        it_should_behave_like "shared CSV behaviors"

        it_should_behave_like "shared non-admin CSV behaviors"
      end

      describe "admin user" do
        before do
          controller.stub(:admin?).and_return(true)
          get_csv_index
        end

        it_should_behave_like "shared CSV behaviors"

        it "should see private fields" do
          @header.should include("Emails")
        end
      end
    end

    shared_examples_for "when exporting" do
      # Expects following to be set by implementor's #before block:
      # - @proposals
      # - @records
      # - @record

      it "should assign multiple items" do
        @proposals.size.should >= 1
      end

      it "should export same number of items as assigned" do
        @records.size.should == @proposals.size
      end

      it "should export presenter" do
        @record.keys.should include('presenter')
      end

      it "should not export email" do
        @record.keys.should_not include('email')
      end

      it "should not export private notes" do
        @record.keys.should_not include('note_to_organizers')
      end
    end

    describe "when returning XML" do
      before(:each) do
        get :index, event_id: @event.slug, format: "xml"

        @proposals = assigns(:proposals)
        @struct = Hash.from_xml(response.body)
        @records = @struct['open_conference_ware_proposals']
        @record = @records.first
      end

      it_should_behave_like "when exporting"
    end

    describe "when returning JSON" do
      before(:each) do
        get :index, event_id: @event.slug, format: "json"

        @proposals = assigns(:proposals)
        @struct = ActiveSupport::JSON.decode(response.body)
        @records = @struct
        @record = @records.first["proposal"]
      end

      it_should_behave_like "when exporting"
    end

    describe "when sorting" do
      it "should sort proposals by title" do
        get :index, sort: "title", event_id: @event.to_param
        extracted = extract_proposals

        extracted.size.should > 0
        values = extracted.map(&:title)
        expected = values.sort_by(&:downcase)
        values.should == expected
      end

      it "should sort proposals by track" do
        get :index, sort: "track", event_id: @event.to_param
        proposals = extract_proposals

        proposals.size.should > 0

        tracks_returned = proposals.map{|proposal| proposal.track.title}
        tracks_expected = tracks_returned.sort_by(&:downcase)
        tracks_returned.should == tracks_expected
      end

      it "should sort proposals by title descending" do
        get :index, sort: "title", dir: "desc", event_id: @event.to_param
        proposals = extract_proposals

        proposals.size.should > 0

        titles_returned = proposals.map(&:title)
        titles_expected = titles_returned.sort_by(&:downcase).reverse
        titles_returned.should == titles_expected
      end

      it "should sort proposals by start time" do
        get :sessions_index, sort: "start_time", event_id: @event.to_param
        proposals = extract_proposals

        proposals.size.should > 0

        values = proposals.map(&:start_time)
        expected = values.sort
        values.should == expected
      end

      it "should not sort proposals by forbidden field" do
        Proposal.any_instance.should_not_receive(:destroy)
        get :index, sort: "destroy", event_id: @event.to_param

        # default to sorting by submitted_at
        proposals = extract_proposals
        proposals.size.should > 0
        values = proposals.map(&:submitted_at)
        expected = values.sort
        values.should == expected
      end

    end

    describe "when returning ATOM" do
      def get_entry(proposal_symbol)
        title = proposals(proposal_symbol).title
        return @doc.xpath("//atom:entry/atom:title[text()='#{title}']", atom:"http://www.w3.org/2005/Atom")
      end

      describe "for /proposals.atom" do
        before do
          get :index, format: "atom"
          @doc = Nokogiri.parse(response.body)
        end

        it "should include proposals from multiple events" do
          get_entry(:clio_chupacabras).should_not be_empty
          get_entry(:aaron_aardvarks).should_not be_empty
        end
      end

      describe "for /events/:event_id/proposals.atom" do
        before do
          get :index, format: "atom", event_id: @event.slug
          @doc = Nokogiri.parse(response.body)
        end

        it "should include proposals from this event" do
          get_entry(:aaron_aardvarks).should_not be_empty
        end

        it "should not include proposals from other events" do
          get_entry(:clio_chupacabras).should be_empty
        end
      end
    end

  end

  describe "sessions" do
    it "should display session_text" do
      event = stub_model(Event,
        :proposal_status_published? => true,
        id: 1234,
        slug: 'event_slug',
        session_text: "MySessionText",
        populated_sessions: []
      )
      stub_current_event!(event: event)

      get :sessions_index, event_id: event.to_param
      response.body.should have_selector(".event_text.session_text") do |text|
        text.should contain("MySessionText")
      end
    end

    it "should display a list of sessions" do
      proposal = stub_model(Proposal, state: "confirmed", users: [])
      proposals = [proposal]
      event = stub_model(Event,
        :proposal_status_published? => true,
        id: 1234,
        slug: 'event_slug',
        populated_sessions: proposals
      )

      stub_current_event!(event: event)

      # Bypass #fetch_object because it can't cache our singleton doubles.
      Proposal.stub(:fetch_object).and_return do |slug, callback|
        callback.call
      end

      get :sessions_index, event_id: event.to_param
      expect(assigns(:proposals)).to be_a_kind_of(proposals.class)
    end

    it "should redirect to proposals unless the proposal status is published" do
      event = stub_model(Event, :proposal_status_published? => false, id: 1234, slug: 'event_slug')
      stub_current_event!(event: event)
      get :sessions_index, event_id: event.to_param

      response.should redirect_to(event_proposals_url(event))
    end

    it "should redirect /sessions to proposals unless proposal status is published" do
      event = stub_model(Event, :proposal_status_published? => false, id: 1234, slug: 'event_slug')
      stub_current_event!(event: event, status: :assigned_to_current)
      get :sessions_index, format: :html

      response.should redirect_to(event_proposals_url(event))
    end

    it "should normalize /sessions if proposal status is published" do
      event = stub_model(Event, :proposal_status_published? => true, id: 1234, slug: 'event_slug')
      stub_current_event!(event: event, status: :assigned_to_current)
      get :sessions_index, format: :html

      response.should redirect_to(event_sessions_path(event))
    end

    it "should normalize /schedule if proposal status is published" do
      event = stub_model(Event, :proposal_status_published? => true, :schedule_published? => true, id: 1234, slug: 'event_slug')
      stub_current_event!(event: event, status: :assigned_to_current)
      get :schedule, format: :html

      response.should redirect_to(event_schedule_path(event))
    end
  end

  describe "show" do
    it "should display extant proposal" do
      proposal = proposals(:quentin_widgets)
      get :show, id: proposal.id

      response.should be_success
      assigns(:proposal).should == proposal
    end

    it "should redirect back to proposals list if asked to display a non-existent proposal" do
      get :show, id: -1

      flash[:failure].should_not be_blank
      response.should redirect_to(proposals_url)
    end

    it "should redirect back to proposals list if asked to display a proposal without an event" do
      proposal = proposals(:quentin_widgets)
      proposal.stub(event: nil)
      Proposal.stub(find_by_id: proposal, find: proposal)

      get :show, id: proposal.id

      flash[:failure].should_not be_blank
      response.should redirect_to(event_proposals_path(events(:open)))
    end

    describe "redirect" do
      # Options:
      # * published: Are proposal statuses published for this event?
      # * confirmed: Is this proposal confirmed?
      # * session: Is this proposal being accessed via a sessions#show route?
      # * redirect: Redirect to where? (:proposal, :session, nil)
      def assert_show(opts={}, &block)
        @key = 123
        @event.stub(:proposal_status_published?).and_return(opts[:published])
        stub_current_event!(event: @event)

        @users = []
        @users.stub(:by_name).and_return([])

        @proposal = stub_model(Proposal, id: @key, event: @event, track: @event.tracks.empty? ? nil : Track.first, users: @users)
        @proposal.stub(:confirmed?).and_return(opts[:confirmed])
        controller.stub(:get_proposal_and_assignment_status).and_return([@proposal, :assigned_via_param])
        get opts[:session] ? :session_show : :show, id: @key
        case opts[:redirect]
        when :proposal
          response.should redirect_to(proposal_path(@key))
        when :session
          response.should redirect_to(session_path(@key))
        when nil, false
          response.should be_success
        else
        end
      end

      describe "when status published" do
        it "should redirect confirmed proposal to session" do
          assert_show published: true, confirmed: true, session: false, redirect: :session
        end

        it "should redirect non-session to proposal" do
          assert_show published: true, confirmed: false, session: true, redirect: :proposal
        end

        it "should display session" do
          assert_show published: true, confirmed: true, session: true, redirect: false
        end

        it "should display proposal" do
          assert_show published: true, confirmed: false, session: false, redirect: false
        end
      end

      describe "when status not published" do
        it "should allow admin to view sessions" do
          login_as :aaron
          assert_show published: false, confirmed: true, session: true, redirect: false
        end

        it "should redirect confirmed proposal to proposals" do
          assert_show published: false, confirmed: true, session: true, redirect: :proposal
        end

        it "should redirect non-session to proposal" do
          assert_show published: false, confirmed: false, session: true, redirect: :proposal
        end

        it "should display confirmed proposal" do
          assert_show published: false, confirmed: true, session: false, redirect: false
        end

        it "should display session as proposal" do
          assert_show published: false, confirmed: false, session: false, redirect: false
        end
      end

      describe "non-current event" do
        render_views false
        it "should not redirect a published session of an old event if current event isn't publishing sesions" do
          current_event = stub_model(Event, slug: 'new', proposal_status_published: false)
          old_event = stub_model(Event, slug: 'old', proposal_status_published: true)
          old_session_user = users(:clio)
          old_session = stub_model(Proposal, status: 'confirmed', event: old_event)
          old_session.users << old_session_user

          Proposal.stub(find: old_session, find_by_id: old_session)
          Event.stub(current: current_event)

          get :session_show, id: old_session.id
          response.should be_success
        end
      end
    end

    describe "accepted proposal" do
      before do
        @proposal = proposals(:quentin_widgets)
        @proposal.accept!
      end

      it "should notify owners of acceptance" do
        login_as(users(:quentin))
        get :show, id: @proposal.id
        response.body.should have_selector("h3", text: 'Congratulations')
      end

      it "should not notify non-owners of acceptance" do
        get :show, id: @proposal.id
        response.body.should_not have_selector("h3", text: 'Congratulations')
      end

      it "should not notify owners of acceptance if proposal confirmation controls are not visible" do
        event = @proposal.event
        event.stub(:show_proposal_confirmation_controls? => false)
        Proposal.stub(find: @proposal)

        login_as(users(:quentin))

        get :show, id: @proposal.id
        response.body.should_not have_selector("h3", text: 'Congratulations')
      end
    end

    describe "not-accepted proposal" do
      before do
        login_as(users(:quentin))
        @proposal = proposals(:quentin_widgets)
      end

      it "should not notify proposed proposal owners of acceptance" do
        get :show, id: @proposal.id
        response.body.should_not have_selector("h3", text: 'Congratulations')
      end

      it "should not notify rejected proposal owners of acceptance" do
        @proposal.reject!
        get :show, id: @proposal.id
        response.body.should_not have_selector("h3", text: 'Congratulations')
      end

      it "should not notify junk proposal owners of acceptance" do
        @proposal.mark_as_junk!
        get :show, id: @proposal.id
        response.body.should_not have_selector("h3", text: 'Congratulations')
      end
    end

  end

  describe "new" do
    describe "for open event" do
      describe "with user_profiles?" do
        before(:each) do
          OpenConferenceWare.stub(have_user_profiles: true)
        end

        it "should redirect incomplete profiles to user edit form" do
          user = users(:incognito)
          login_as(user)
          get :new, event_id: events(:open).slug

          flash.keys.should include(:notice)
          response.should redirect_to(edit_user_path(user, require_complete_profile: true))
        end

        it "should allow users with complete profiles" do
          login_as(:quentin)
          get :new, event_id: events(:open).slug

          flash.keys.should_not include(:failure)
          response.should be_success
        end
      end

      describe "without user_profiles?" do
        before(:each) do
          OpenConferenceWare.stub(have_user_profiles: false)
        end

        describe "with anonymous_proposals" do
          before(:each) do
            OpenConferenceWare.stub(have_anonymous_proposals: true)
          end

          it "should display form for open events" do
            get :new, event_id: events(:open).slug

            response.should be_success
            assigns(:proposal).should be_true
          end

          it "should not assign presenter if anonymous" do
            logout
            get :new, event_id: events(:open).slug

            response.should be_success
            proposal = assigns(:proposal)
            proposal.presenter.should be_blank
          end
        end

        describe "without anonymous_proposals" do
          before(:each) do
            OpenConferenceWare.stub(have_anonymous_proposals: false)
          end

          it "should redirect anonymous user to login" do
            get :new, event_id: events(:open).slug

            flash.keys.should include(:notice)
            response.should redirect_to(sign_in_path)
          end
        end

        it "should assign presenter if logged in" do
          user = users(:quentin)
          login_as(user)
          get :new, event_id: events(:open).slug

          response.should be_success
          proposal = assigns(:proposal)
          proposal.presenter.should == user.fullname
        end

        describe "when an event can have tracks" do
          it "should assign a track if there's only one" do
            event = create(:event)
            event.session_types << build(:session_type)
            track = create(:track, event: event)
            user = create(:user)
            login_as(user)

            get :new, event_id: event.slug

            flash[:failure].should be_nil
            assigns(:proposal).track.should == track
          end

          it "should not assign a track if there's more than one" do
            event = create(:event)
            event.session_types << build(:session_type)
            track1 = create(:track, event: event)
            track2 = create(:track, event: event)
            user = create(:user)
            login_as(user)

            get :new, event_id: event.slug

            flash[:failure].should be_nil
            assigns(:proposal).track.should be_nil
          end
        end

        describe "when event can have session types" do
          it "should assign a session type if there's only one" do
            event = create(:event)
            event.tracks << build(:track)
            session_type = create(:session_type, event: event)
            user = create(:user)
            login_as(user)

            get :new, event_id: event.slug

            assigns(:proposal).session_type.should == session_type
          end

          it "should not assign a session type if there's more than one" do
            event = create(:event)
            event.tracks << build(:track)
            session_type1 = create(:session_type, event: event)
            session_type2 = create(:session_type, event: event)
            user = create(:user)
            login_as(user)

            get :new, event_id: event.slug

            assigns(:proposal).session_type.should be_nil
          end
        end
      end
    end

    describe "with closed event" do
      it "should not display form" do
        login_as(users(:quentin))
        event = events(:closed)
        get :new, event_id: event.to_param

        response.should redirect_to(event_proposals_path(event))
      end
    end
  end

  describe "edit" do
    before do
      @proposal = proposals(:quentin_widgets)
    end

    shared_examples_for "shared allowed edit behaviors" do
      it "should not redirect with failure" do
        get :edit, id: @proposal.id, event_id: @event.to_param
        flash.keys.should_not include(:failure)
        response.should be_success
      end
    end

    shared_examples_for "shared forbidden edit behaviors" do
      it "should redirect with failure" do
        get :edit, id: @proposal.id, event_id: @event.to_param
        flash.keys.should include(:failure)
        response.should redirect_to(proposal_path(@proposal))
      end
    end

    describe "anonymous user" do
      before(){ logout }

      it "should redirect to login" do
        get :edit, id: @proposal.id, event_id: @event.to_param
        response.should redirect_to(sign_in_path)
      end
    end

    describe "non-owner mortal user" do
      before(){ login_as :clio }
      it_should_behave_like "shared forbidden edit behaviors"
    end

    describe "owner mortal user" do
      before(){ login_as :quentin }
      it_should_behave_like "shared allowed edit behaviors"
    end

    describe "admin user" do
      before { login_as :aaron }
      it_should_behave_like "shared allowed edit behaviors"
    end

    describe "when closed" do
      it "should redirect if owner tries to edit proposal for closed event" do
        proposal = proposals(:clio_chupacabras)
        login_as :clio
        get :edit, id: proposal.id

        pending "FIXME when should people not be able to edit proposals?"
        response.should redirect_to(event_proposals_path(proposal.event))
      end

      it "should allow admin to edit" do
        proposal = proposals(:clio_chupacabras)
        login_as :aaron
        get :edit, id: proposal.id

        response.should be_success
        assigns(:proposal).should == proposal
      end
    end
  end

  describe "create" do
    # Try to create a proposal.
    #
    # Arguments:
    # * login: User to login as, can be nil for none, symbol or user object.
    # * inputs: Hash of properties to create a proposal from.
    def assert_create(login=nil, inputs={}, &block)
      login ? login_as(login) : logout
      # TODO extract :commit into separate argument
      post :create, inputs.reverse_merge(commit: 'really')
      @record = assigns(:proposal)
      block.call
    end

    before do
      # TODO test other settings combinations
      OpenConferenceWare.stub(have_proposal_excerpts: false)
      OpenConferenceWare.stub(have_multiple_presenters: false)
      OpenConferenceWare.stub(have_user_profiles: false)

      @inputs = proposals(:quentin_widgets).attributes
      @record = nil
    end

    describe "with user_profiles?" do
      before(:each) do
        OpenConferenceWare.stub(have_user_profiles: true)
      end

      it "should fail to create proposal without a complete user" do
        user = users(:quentin)
        user.should_receive(:complete_profile?).at_least(:once).and_return(false)
        User.should_receive(:find).and_return(user)
        proposal = Proposal.new(@inputs)
        proposal.users << user
        Proposal.should_receive(:new).and_return(proposal)
        assert_create(user, event_id: @event.slug, proposal: @inputs) do
          response.should be_success
          proposal = assigns(:proposal)
          proposal.should_not be_valid
        end
      end
    end

    describe "without user_profiles?" do
      before(:each) do
        OpenConferenceWare.stub(have_user_profiles: false)
      end

      describe "with anonymous proposals" do
        before(:each) do
          OpenConferenceWare.stub(have_anonymous_proposals: true)
        end

        it "should create proposal for anonymous user" do
          assert_create(nil, event_id: @event.slug, proposal: @inputs) do
            proposal = assigns(:proposal)
            proposal.should be_valid
            proposal.id.should_not be_nil
          end
        end

        it "should preview proposal for anonymous user" do
          @inputs['title'] = ''
          assert_create(nil, event_id: @event.slug, proposal: @inputs, submit: nil, preview: 'Preview') do
            proposal = assigns(:proposal)
            proposal.errors.should_not be_empty
            proposal.should_not be_valid
            proposal.id.should be_nil
          end
        end
      end

      describe "without anonymous proposals" do
        before(:each) do
          OpenConferenceWare.stub(have_anonymous_proposals: false)
        end

        it "should not create proposal for anonymous user" do
          assert_create(nil, event_id: @event.slug, proposal: @inputs) do
            response.should redirect_to(sign_in_path)
          end
        end
      end

      it "should create proposal for mortal user" do
        assert_create(:quentin, event_id: @event.slug, proposal: @inputs) do
          proposal = assigns(:proposal)
          proposal.should be_valid
          proposal.id.should_not be_nil
        end
      end

      it "should fail to create proposal without a presenter" do
        inputs = @inputs.clone
        inputs['presenter'] = nil
        assert_create(:quentin, event_id: @event.slug, proposal: inputs) do
          response.should be_success
          proposal = assigns(:proposal)
          proposal.should_not be_valid
        end
      end
    end

    describe "success page" do
      before(:each) do
        login_as(:quentin)
        @proposal = stub_model(Proposal, id: 123)
        @proposal.should_receive(:save).and_return(true)
        @proposal.should_receive(:add_user).and_return(true)
        Proposal.should_receive(:new).and_return(@proposal)
      end

      it "should display success page" do
        @controller.should_receive(:render).and_return("My HTML here")

        post :create, commit: "Create", proposal: {foo: 'bar'}
      end
    end

  end

  describe "update" do
    def assert_update(login=nil, inputs={}, optional_params={}, &block)
      login ? login_as(login) : logout
      optional_params.reverse_merge commit: 'really'
      put :update, { id: ( inputs['id'] || inputs[:id] ), proposal: inputs }.merge(optional_params)
      block.call
    end

    before do
      @user = users(:quentin)
      @proposal = proposals(:quentin_widgets)
      @inputs = @proposal.attributes
    end

    it "should prevent editing of title when proposal titles are locked" do
      @event = stub_current_event!
      @event.stub(:proposal_titles_locked?).and_return(true)
      @controller.stub(:get_proposal_and_assignment_status).and_return(@proposal)
      @proposal.stub(:event).and_return(@event)

      assert_update(:quentin, id: @proposal.id, title: 'OMG') do
        @proposal.reload
        @proposal.title.should_not == 'OMG'
      end
    end

    it "should redirect anonymous user to login" do
      assert_update(nil, @inputs) do
        response.should redirect_to(sign_in_path)
      end
    end

    it "should reject non-owner mortal user" do
      assert_update(:clio, @inputs) do
        flash.keys.should include(:failure)
        response.should redirect_to(proposal_url(@proposal))
      end
    end

    describe "when settings status" do
      it "should allow admin to change status" do
        @inputs[:transition] = 'accept'
        @controller.should_receive(:get_proposal_and_assignment_status).and_return([@proposal, :assigned_via_param])
        @proposal.should_receive(:accept!)
        assert_update(:aaron, @inputs) do
          # Everything is done through the should_receive
        end
      end

      it "should not allow non-admin to change status" do
        @inputs[:transition] = 'accept'
        @controller.should_receive(:get_proposal_and_assignment_status).and_return([@proposal, :assigned_via_param])
        @proposal.should_not_receive(:accept!)
        assert_update(:quentin, @inputs) do
        end
      end
    end

    describe "with user_profiles?" do
      before(:each) do
        OpenConferenceWare.stub(have_user_profiles: true)
      end

      it "should specify update behavior"
    end

    describe "without user_profiles?" do
      before(:each) do
        OpenConferenceWare.stub(have_user_profiles: false)
      end

      it "should display edit form if fields are invalid" do
        inputs = @inputs.clone
        inputs['presenter'] = nil
        assert_update(:quentin, inputs) do
          response.should be_success
          response.should render_template('edit')
        end
      end

      it "should allow owner mortal user" do
        assert_update(:quentin, @inputs) do
          flash.keys.should include(:success)
          response.should redirect_to(proposal_url(@proposal))
        end
      end

      it "should display preview" do
        assert_update(:quentin, @inputs, { commit: nil, preview: 'Preview' }) do
          response.should be_success
          response.should render_template('edit')
        end
      end

      it "should allow admin user" do
        assert_update(:aaron, @inputs) do
          flash.keys.should include(:success)
          response.should redirect_to(proposal_url(@proposal))
        end
      end
    end
  end

  describe "delete" do
    before do
      @proposal = proposals(:quentin_widgets)
      Proposal.stub(:find).and_return(@proposal)
    end

    def assert_delete(login=nil, &block)
      login ? login_as(login) : logout
      delete :destroy, id: @proposal.id
      block.call
    end

    it "should ask anonymous to login" do
      @proposal.should_not_receive(:destroy)
      assert_delete do
        response.should redirect_to(sign_in_path)
      end
    end

    it "should reject non-owner mortal user" do
      @proposal.should_not_receive(:destroy)
      assert_delete(:clio) do
        flash.keys.should include(:failure)
        response.should redirect_to(proposal_url(@proposal))
      end
    end

    it "should allow owner mortal user" do
      @proposal.should_receive(:destroy)
      assert_delete(:quentin) do
        flash.keys.should include(:success)
        response.should redirect_to(event_proposals_url(@proposal.event))
      end
    end

    it "should allow admin user" do
      @proposal.should_receive(:destroy)
      assert_delete(:quentin) do
        flash.keys.should include(:success)
        response.should redirect_to(event_proposals_url(@proposal.event))
      end
    end
  end

  describe "schedule" do
    it "should not fail like a whale" do
      @controller.stub(:schedule_visible?).and_return(true)
      item = proposals(:postgresql_session)

      get :schedule, event_id: @event.slug

      response.should be_success
      response.body.should have_selector(".summary", text: item.title)
    end

    it "should not fail like a whale with iCalendar" do
      @controller.stub(:schedule_visible?).and_return(true)
      item = proposals(:postgresql_session)

      get :schedule, event_id: @event.slug, format: "ics"

      response.should be_success
      calendar = Vpim::Icalendar.decode(response.body).first
      component = calendar.find{|t| t.summary == item.title}

      dtstart = Time.parse(component.dtstart.strftime('%Y-%m-%d %H:%M:%S UTC'))
      dtend   = Time.parse(component.dtend.strftime('%Y-%m-%d %H:%M:%S UTC'))

      component.should_not be_nil
      dtstart.should  == item.start_time
      dtend.should    == item.end_time
      component.summary.should      == item.title
      component.description.should  == (item.respond_to?(:users) ?
        "#{item.users.map(&:fullname).join(', ')}: #{item.excerpt}" :
        item.excerpt)
      component.url                 == session_url(item)
    end
  end

  describe "manage speakers" do
    before(:each) do
      OpenConferenceWare.stub(have_user_profiles: true)
      @bubba = stub_model(User, fullname: "Bubba Smith")
      @billy = stub_model(User, fullname: "Billy Jack")
      @sue = stub_model(User, fullname: "Sue Smith")
      @proposal = stub_model(Proposal)
      @proposal.users = [@bubba, @billy]
      @event = stub_current_event!
      controller.stub(:assign_get_proposal_for_speaker_manager)
      controller.stub(:get_proposal_for_speaker_manager).and_return(@proposal)
    end

    it "should list" do
      get :manage_speakers, speakers: "#{@bubba.id},#{@billy.id}", id: @proposal.to_param
      response.body.should have_selector(".speaker_id[name='speaker_ids[#{@bubba.id}]']")
      response.body.should have_selector(".speaker_id[name='speaker_ids[#{@billy.id}]']")
      response.body.should_not have_selector(".speaker_id[name='speaker_ids[#{@sue.id}]']")
    end

    it "should add user" do
      User.should_receive(:find).and_return(@sue)
      get :manage_speakers, speakers: "#{@bubba.id},#{@billy.id}", add: @sue.id, id: @proposal.to_param
      response.body.should have_selector(".speaker_id[name='speaker_ids[#{@bubba.id}]']")
      response.body.should have_selector(".speaker_id[name='speaker_ids[#{@billy.id}]']")
      response.body.should have_selector(".speaker_id[name='speaker_ids[#{@sue.id}]']")
    end

    it "should remove user" do
      User.should_receive(:find).and_return(@billy)
      get :manage_speakers, speakers: "#{@bubba.id},#{@billy.id}", remove: @billy.id, id: @proposal.to_param
      response.body.should have_selector(".speaker_id[name='speaker_ids[#{@bubba.id}]']")
      response.body.should_not have_selector(".speaker_id[name='speaker_ids[#{@billy.id}]']")
    end
  end

  describe "search speakers" do
    before(:each) do
      @proposal = stub_model(Proposal)

      @bubba = stub_model(User, fullname: "Bubba Smith")
      @billy = stub_model(User, fullname: "Billy Smith")
      @john = stub_model(User, fullname: "John Doe")

      @params = {
        search: "smith",
        speakers: "IGNORED",
      }

      User.should_receive(:complete_profiles).and_return([@bubba, @john, @billy])
    end

    describe "new record" do
      before(:each) do
        @params[:id] = "new_record"
        Proposal.should_receive(:new).and_return(@proposal)
        @proposal.should_receive(:add_user)
      end

      it "should match users that aren't in the proposal" do
        @proposal.should_receive(:users).and_return([])
        post :search_speakers, @params
        assigns(:matches).should == [@bubba, @billy]
      end

      it "should not match users that are in the proposal" do
        @proposal.should_receive(:users).and_return([@bubba])
        post :search_speakers, @params
        assigns(:matches).should == [@billy]
      end
    end

    describe "existing record" do
      before(:each) do
        @proposal.id = 123
        @proposal.event = events(:open)
        @params[:id] = @proposal.id
        Proposal.stub(:find).and_return(@proposal)
      end

      it "should match users that aren't in the proposal" do
        @proposal.should_receive(:users).and_return([])
        post :search_speakers, @params
        assigns(:matches).should == [@bubba, @billy]
      end

      it "should not match users that are in the proposal" do
        @proposal.should_receive(:users).and_return([@bubba])
        post :search_speakers, @params
        assigns(:matches).should == [@billy]
      end
    end
  end

  def assert_confirmed
    post :speaker_confirm, id: @proposal.id
    @proposal.reload
    @proposal.status.should == 'confirmed'
    flash[:success].should =~ /Updated/
  end

  def assert_not_confirmed
    post :speaker_confirm, id: @proposal.id
    @proposal.reload
    @proposal.status.should_not == 'confirmed'
    flash[:success].should_not =~ /Updated/
  end

  describe "proposal login required" do
      it "should redirect to login if not logged in" do
        proposal = proposals(:quentin_widgets)
        get :proposal_login_required, proposal_id: proposal.id
        response.should redirect_to(sign_in_path)
      end

      it "should redirect to proposal if logged in" do
        login_as(users(:quentin))
        proposal = proposals(:quentin_widgets)
        get :proposal_login_required, proposal_id: proposal.id
        response.should redirect_to(proposal_path(proposal))
      end
  end

  describe "speaker confirm" do
    describe "accepted proposal" do
      before(:each) do
        @proposal = proposals(:quentin_widgets)
        @proposal.accept!
      end

      it "should confirm for owners of the proposal" do
        login_as(users(:quentin))
        assert_confirmed
      end
      it "should not confirm for non-owners of the proposal" do
        login_as(users(:aaron))
        assert_not_confirmed
      end
    end

    describe "not-accepted proposal" do
      before(:each) do
        @proposal = proposals(:quentin_widgets)
      end

      it "should not confirm for owners of the proposal" do
        login_as(users(:quentin))
        lambda { post :speaker_confirm, id: @proposal.id }.should raise_error(AASM::InvalidTransition)
      end
      it "should not confirm for non-owners of the proposal" do
        login_as(users(:aaron))
        assert_not_confirmed
      end
    end
  end

  def assert_declined
    post :speaker_decline, id: @proposal.id
    @proposal.reload
    @proposal.status.should == 'declined'
    flash[:success].should =~ /Updated/
  end

  def assert_not_declined
    post :speaker_decline, id: @proposal.id
    @proposal.reload
    @proposal.status.should_not == 'declined'
    flash[:success].should_not =~ /Updated/
  end

  describe "speaker decline" do
    describe "accepted proposal" do
      before(:each) do
        @proposal = proposals(:quentin_widgets)
        @proposal.accept!
      end

      it "should decline for owners of the proposal" do
        login_as(users(:quentin))
        assert_declined
      end
      it "should not decline for non-owners of the proposal" do
        login_as(users(:aaron))
        assert_not_declined
      end
    end

    describe "not-accepted proposal" do
      before(:each) do
        @proposal = proposals(:quentin_widgets)
      end

      it "should not decline for owners of the proposal" do
        login_as(users(:quentin))
        lambda { post :speaker_decline, id: @proposal.id }.should raise_error(AASM::InvalidTransition)
      end
      it "should not decline for non-owners of the proposal" do
        login_as(users(:aaron))
        assert_not_declined
      end
    end
  end

  describe "get_proposal_and_assignment_status" do
    it "should return a status of :invalid_proposal when no proposal id is given" do
      @controller.stub(:params).and_return({ id: nil })
      @controller.send(:get_proposal_and_assignment_status).should == [nil, :invalid_proposal]
    end

    it "should return a status of :invalid_event when a proposal doesn't have a valid event" do
      proposal = stub_model(Proposal, state: "confirmed", event: nil)
      Proposal.stub(:find).and_return(proposal)
      @controller.stub(:params).and_return({ id: 1000 })
      @controller.send(:get_proposal_and_assignment_status).should == [proposal, :invalid_event]
    end
  end

  describe "assign_proposal_and_event" do

    it "should return false and not redirect when proposal and its event are successfully found" do
      proposal = stub_model(Proposal, state: "confirmed", event: @event)
      @controller.should_receive(:get_proposal_and_assignment_status).and_return([proposal, :assigned_via_param])
      @controller.send(:assign_proposal_and_event).should == false
      flash[:failure].should be_nil
    end

    it "should redirect when proposal assignment status is :invalid_proposal" do
      proposal = stub_model(Proposal, event: @event)
      @controller.should_receive(:get_proposal_and_assignment_status).and_return([proposal, :invalid_proposal])
      @controller.should_receive(:redirect_to)
      @controller.send(:assign_proposal_and_event)
      flash[:failure].should == "Sorry, that presentation proposal doesn't exist or has been deleted."
    end

    it "should redirect when proposal assignment status is :invalid_event" do
      proposal = stub_model(Proposal, state: "confirmed", event: nil, id: 1)
      @controller.should_receive(:get_proposal_and_assignment_status).and_return([proposal, :invalid_event])
      @controller.should_receive(:redirect_to)
      @controller.send(:assign_proposal_and_event)
      flash[:failure].should == "Sorry, no event was associated with proposal #1"
    end
  end

end
