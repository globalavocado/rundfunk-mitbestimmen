require 'rails_helper'

RSpec.describe 'Broadcasts', type: :request do
  let(:headers) { {} }
  let(:params)  { {} }
  let(:setup) { }
  let(:user) { create :user }

  let(:tv)    { Medium.create(id: 0, name: 'tv') }
  let(:radio) { Medium.create(id: 1, name: 'radio') }
  let(:other) { Medium.create(id: 2, name: 'other') }

  let(:dasErste) { create(:station, id: 47, name: 'Das Erste') }

  describe 'GET' do
    let(:action) { get url, params: params, headers: headers }

    before do
      setup
      action
    end

    describe '/broadcasts' do
      let(:url) { '/broadcasts' }
      subject { response.body }

      context 'given some broadcasts' do
        let(:broadcasts) {  create_list(:broadcast, 23) }
        let(:setup) { broadcasts }

        describe 'relationships' do
          describe '#medium' do
            let(:setup) { create(:broadcast, id: 0, medium: tv) }
            subject { parse_json(response.body, 'data/0/relationships/medium/data/id') }
            it { is_expected.to eq(tv.id.to_s) }
          end

          describe '#impressions' do
            let(:setup) { create(:impression) }
            subject { parse_json(response.body, 'data/0/relationships/impressions/data') }
            it 'are not exposed' do
              is_expected.to be_empty
            end
          end
        end

        describe 'pagination' do
          it { is_expected.to have_json_size(10).at_path('data') }
          it { expect(parse_json(subject, 'meta/total-count')).to eq(23) }

          context '?page=' do
            let(:params) { { page: 3 } }
            it { is_expected.to have_json_size(3).at_path('data') }
          end

          context '?per_page=' do
            let(:params) { { per_page: 23 } }
            it { is_expected.to have_json_size(23).at_path('data') }
          end
        end
      end
    end
  end

  describe 'POST' do
    before { setup }
    let(:setup) { radio }
    let(:action) { post url, params: params, headers: headers }

    describe '/broadcasts' do
      let(:url) { '/broadcasts' }

      let(:params) do
        {
          data: {
            type: 'broadcasts',
            attributes: {
              title: 'Nice broadcast',
              description: 'A nice broadcast, everybody will love it'
            }, relationships: {
              medium: {
                data: {
                  id: '1',
                  type: 'media'
                }
              }
            }
          }
        }
      end


      context 'logged in' do
        let(:headers) { super().merge(authenticated_header(user)) }

        describe 'creates a broadcast' do
          specify { expect{ action}.to(change{Broadcast.count}.from(0).to(1)) }

          describe 'associated medium' do
            subject { Broadcast.first.medium }
            before { action }
            it { is_expected.to eq radio }
          end
        end

        context 'duplicate broadcast' do
          let(:setup) do
            create(:broadcast, title: 'Nice broadcast')
            super()
          end

          describe 'error message' do
            before { action }
            subject { parse_json(response.body, 'errors/0/detail') }
            it { is_expected.to eq('ist bereits vergeben') }
          end
        end

        [:contributor, :admin].each do |role|
          context "as #{role}" do
            let(:user) { create(:user, role) }
            it 'allowed to create new broadcasts' do
              expect { action }.to(change { Broadcast.count })
              expect(response).to have_http_status(:created)
            end

            describe 'creator' do
              subject { User.find(Broadcast.first.versions.last.whodunnit) }
              before { action }
              it { is_expected.to eq user }
            end
          end
        end
      end
    end
  end

  describe 'PATCH' do
    let(:action) { patch url, params: params, headers: headers }
    before { setup }

    describe '/broadcasts' do
      let(:url) { "/broadcasts/#{broadcast.id}" }

      context 'logged in' do
        let(:headers) { super().merge(authenticated_header(user)) }
        let(:user) { create(:user) }

        context 'given some broadcast' do
          let(:setup) do
            other # noise
            dasErste # create a station
            broadcast
          end
          let(:broadcast) { create(:broadcast, id: 0, medium: tv) }

          describe 'change medium and station' do
            let(:params) do
              {
                data: {
                  type: 'broadcasts',
                  attributes: {
                  }, relationships: {
                    medium: {
                      data: {
                        id: '2',
                        type: 'media'
                      }
                    },
                    stations: {
                      data: [{
                        id: '47',
                        type: 'stations'
                      }]
                    }
                  }
                }
              }

              it 'is allowed to change medium of a broadcast' do
                expect { action }.to(change{ Broadcas.find(0).medium }.from(tv).to(other))
              end

              it 'is allowed to add a new station to a broadcasts' do
                expect { action }.to(change{ Broadcast.find(0).stations.to_a }.from([]).to([dasErste]))
              end
            end
          end

          describe 'remove stations' do
            let(:broadcast) { create(:broadcast, id: 0, stations: [dasErste]) }
            let(:params) do
              {
                data: {
                  type: 'broadcasts',
                  attributes: {
                  }, relationships: {
                    stations: {
                      data: []
                    }
                  }
                }
              }
            end

            it 'is allowed to remove stations' do
              expect { action }.to(change{ Broadcast.find(0).stations.to_a }.from([dasErste]).to([]))
            end

            describe 'papertrail' do
              specify { expect { action }.to(change { PaperTrail::Version.count }.by(1)) }

              describe 'deleted schedule' do
                before { action }
                let(:deleted_schedule) { PaperTrail::Version.where(item_type: 'Schedule').last.reify }

                describe 'station' do
                  subject { deleted_schedule.station }
                  it { is_expected.to eq dasErste }
                end

                describe 'broadcast' do
                  subject { deleted_schedule.broadcast }
                  it { is_expected.to eq broadcast }
                end
              end
            end

            describe 'whodunnit' do
              before { action }
              subject { PaperTrail::Version.last.whodunnit.to_i }
              it { is_expected.to eq user.id }
            end
          end
        end
      end
    end
  end

  describe 'DELETE' do
    let(:action) { delete url, params: params, headers: headers }
    before { setup }

    describe '/broadcasts/:id' do
      let(:url) { "/broadcasts/#{broadcast.id}" }

      context 'given a broadcast' do
        let(:setup) { broadcast }
        let(:broadcast) { create(:broadcast) }

        context 'logged in' do
          let(:headers) { super().merge(authenticated_header(user)) }

          context 'as contributor' do
            let(:user) { create(:user, :contributor) }

            describe 'not allowed to delete broadcasts' do
              specify { expect { action }.not_to(change { Broadcast.count }) }

              describe 'http status' do
                before { action }
                subject { response }
                it { is_expected.to have_http_status(:forbidden) }
              end
            end
          end

          context 'as admin' do
            let(:user) { create(:user, :admin) }
            describe 'allowed to delete broadcasts' do
              specify { expect { action }.to(change { Broadcast.count }.from(1).to(0)) }

              describe 'http status' do
                before { action }
                subject { response }
                it { is_expected.to have_http_status(:no_content) }
              end
            end
          end
        end
      end
    end
  end
end
