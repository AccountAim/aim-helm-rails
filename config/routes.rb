AimHelmRails::Engine.routes.draw do
  resources :attachments, only: %i[create show] do
    get :thumbnail, on: :member
  end

  resources :chats, only: [] do
    resources :messages, only: :create, module: :chats
  end
end
