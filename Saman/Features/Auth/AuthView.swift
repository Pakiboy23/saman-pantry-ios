import SwiftUI

struct AuthView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    private var auth: AuthService { appEnv.auth }

    var body: some View {
        if auth.pendingEmailConfirmation {
            confirmationView
        } else {
            formView
        }
    }

    private var confirmationView: some View {
        ZStack {
            Color.surfaceDoodh.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 6) {
                    Text("Saman")
                        .font(.cormorant(size: 52, weight: .bold))
                        .foregroundStyle(Color.brandSaag)
                    Text("سامان")
                        .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                        .foregroundStyle(Color.inkKohlSoft)
                }
                Spacer().frame(height: 48)
                Image(systemName: "envelope.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.brandSaag)
                Spacer().frame(height: 24)
                Text("Check your email")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.inkKohl)
                Spacer().frame(height: 10)
                Text("We sent a confirmation link to\n\(auth.pendingEmail)")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.inkKohlSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Saman.Space.md)
                Spacer().frame(height: 40)
                Button {
                    Task { await auth.resendConfirmation() }
                } label: {
                    Group {
                        if auth.isLoading {
                            ProgressView().tint(Color.surfaceDoodh)
                        } else {
                            Text("Resend email")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.surfaceDoodh)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.brandSaag, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
                }
                .disabled(auth.isLoading)
                .padding(.horizontal, Saman.Space.md)
                if let error = auth.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentAnaar)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Saman.Space.md)
                }
                Spacer().frame(height: 16)
                Button {
                    auth.cancelConfirmation()
                } label: {
                    Text("Back to Sign In")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.brandSaag)
                }
                Spacer()
            }
        }
    }

    private var formView: some View {
        ZStack {
            Color.surfaceDoodh.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 72)

                    // Wordmark
                    VStack(spacing: 6) {
                        Text("Saman")
                            .font(.cormorant(size: 52, weight: .bold))
                            .foregroundStyle(Color.brandSaag)
                        Text("سامان")
                            .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                            .foregroundStyle(Color.inkKohlSoft)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer().frame(height: 40)

                    // Form card
                    VStack(spacing: 14) {
                        // Email
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.inkKohlSoft)
                                .kerning(0.8)
                            ZStack(alignment: .leading) {
                                if email.isEmpty {
                                    Text("you@example.com")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.inkKohlSoft)
                                        .padding(.horizontal, 14)
                                        .allowsHitTesting(false)
                                }
                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.inkKohl)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                            }
                            .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Saman.Radius.md)
                                    .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                            )
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.inkKohlSoft)
                                .kerning(0.8)
                            SecureField("••••••••", text: $password)
                                .textContentType(isSignUp ? .newPassword : .password)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.inkKohl)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(Color.surfaceAtta, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Saman.Radius.md)
                                        .stroke(Color.borderAkhrotSoft.opacity(0.5), lineWidth: 1)
                                )
                        }

                        // Error message
                        if let error = auth.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.accentAnaar)
                                    .font(.system(size: 13))
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.accentAnaar)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, Saman.Space.md)

                    Spacer().frame(height: 24)

                    // Primary action button
                    Button {
                        Task {
                            if isSignUp {
                                await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        Group {
                            if auth.isLoading {
                                ProgressView().tint(Color.surfaceDoodh)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(Color.surfaceDoodh)
                        .background(
                            email.isEmpty || password.isEmpty
                                ? Color.brandSaag.opacity(0.45)
                                : Color.brandSaag,
                            in: RoundedRectangle(cornerRadius: Saman.Radius.md)
                        )
                    }
                    .disabled(email.isEmpty || password.isEmpty || auth.isLoading)
                    .padding(.horizontal, Saman.Space.md)

                    Spacer().frame(height: 20)

                    // Toggle sign-in / sign-up
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            auth.errorMessage = nil
                        }
                    } label: {
                        Text(
                            "\(Text(isSignUp ? "Already have an account? " : "Don't have an account? ").foregroundStyle(Color.inkKohlSoft))\(Text(isSignUp ? "Sign In" : "Create account").foregroundStyle(Color.brandSaag))"
                        )
                    }
                    .font(.system(size: 14))

                    Spacer().frame(height: 48)
                }
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(\.appEnv, AppEnvironment(modelContainer: .preview))
}
