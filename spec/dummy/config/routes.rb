Rails.application.routes.draw do
  mount AimHelmRails::Engine => "/helm", as: :aim_helm_rails
end
