import SwiftUI

struct AuthView: View {
    @Environment(\.appEnv) private var appEnv
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    private var auth: AuthService { appEnv.auth }

    var body: some View {
        ZStack {
            Color.samanBg.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 72)

                    // Wordmark
                    VStack(spacing: 6) {
                        Text("Saman")
                            .font(.cormorant(52))
                            .foregroundStyle(Color.samanPrimary)
                        Text("سامان")
                            .font(.custom("NotoNastaliqUrdu-Regular", size: 22))
                            .foregroundStyle(Color.samanAccent)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer().frame(height: 40)

                    // Form card
                    VStack(spacing: 14) {
                        // Email
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EMAIL")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.samanMuted)
                                .kerning(0.8)
                            ZStack(alignment: .leading) {
                                if email.isEmpty {
                                    Text("you@example.com")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: "9A8472"))
                                        .padding(.horizontal, 14)
                                        .allowsHitTesting(false)
                                }
                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.samanPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                            }
                            .background(Color.samanDeep, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Saman.Radius.md)
                                    .stroke(Color.samanBorder, lineWidth: 1)
                            )
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PASSWORD")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.samanMuted)
                                .kerning(0.8)
                            SecureField("••••••••", text: $password)
                                .textContentType(isSignUp ? .newPassword : .password)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.samanPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(Color.samanDeep, in: RoundedRectangle(cornerRadius: Saman.Radius.md))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Saman.Radius.md)
                                        .stroke(Color.samanBorder, lineWidth: 1)
                                )
                        }

                        // Error message
                        if let error = auth.errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.samanRed)
                                    .font(.system(size: 13))
                                Text(error)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.samanRed)
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
                                ProgressView().tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(
                            email.isEmpty || password.isEmpty
                                ? Color(hex: "C67E2A").opacity(0.45)
                                : Color(hex: "C67E2A"),
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
                            "\(Text(isSignUp ? "Already have an account? " : "Don't have an account? ").foregroundStyle(Color.samanMuted))\(Text(isSignUp ? "Sign In" : "Create account").foregroundStyle(Color.samanAccent))"
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
