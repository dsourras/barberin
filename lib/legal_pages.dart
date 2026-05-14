part of 'main.dart';

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF2E3C8),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: Color(0xFFE8DCC9),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalPageScaffold extends StatelessWidget {
  const _LegalPageScaffold({
    required this.title,
    required this.sections,
  });

  final String title;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFF2E3C8),
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections,
            ),
          ),
        ],
      ),
    );
  }
}

class BarberoPrivacyPolicyPage extends StatelessWidget {
  const BarberoPrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalPageScaffold(
      title: 'Privacy Policy',
      sections: [
        _LegalSection(
          title: '1. Scope',
          body:
              'This Privacy Policy explains how Barbero collects, uses, stores, and safeguards information when barber shop owners, managers, barbers, assistants, and authorized staff use the Barbero software platform. Barbero is a business management application used to operate barber shops, manage appointments, manage teams, review client history, configure services and pricing, monitor reports, and support day-to-day business workflows.',
        ),
        _LegalSection(
          title: '2. Categories of Data We Process',
          body:
              'Barbero may process account data such as names, email addresses, phone numbers, profile images, authentication identifiers, and role assignments. It may also process shop data such as shop name, schedule settings, pricing, barber profiles, service specialties, blocked slots, operational notes, reports, and notification tokens. In addition, Barbero may process customer-related information entered by the shop, including appointment history, selected services, preferences, notes, phone numbers, email addresses, and profile images where the shop chooses to store them.',
        ),
        _LegalSection(
          title: '3. Why We Use Data',
          body:
              'We use data to provide the software service, authenticate users, distinguish owners from invited crew members, synchronize shop records across devices, support scheduling and booking logic, enable appointment lifecycle actions, deliver operational notifications, generate analytics and revenue reporting, help shops review customer preferences, and maintain the security and integrity of the platform.',
        ),
        _LegalSection(
          title: '4. Customer Data Managed by Shops',
          body:
              'Barbero is a software tool for businesses. Shop owners and their authorized crew members are responsible for the customer information they enter, review, or maintain in the application. Where Barbero processes customer information on behalf of a shop, that shop remains responsible for ensuring that it has the appropriate right, notice, or legal basis to use that information for appointment scheduling, communication, and client relationship management.',
        ),
        _LegalSection(
          title: '5. Notifications and Device Tokens',
          body:
              'Barbero may store device notification tokens so that the application can send operational alerts such as new bookings, updates to appointments, cancellations, reminders, or crew-related actions. These tokens are used only to deliver service-related notifications associated with the relevant account or shop workflow.',
        ),
        _LegalSection(
          title: '6. Data Sharing and Service Providers',
          body:
              'Barbero relies on infrastructure and cloud services used to operate the application, including authentication, cloud functions, storage, databases, and messaging tools. Data may therefore be processed by technology providers acting as hosting, infrastructure, communications, or support providers for the purpose of delivering the service. We do not sell customer or shop data as part of the normal operation of the software.',
        ),
        _LegalSection(
          title: '7. Data Retention',
          body:
              'We retain live operational data for as long as the relevant shop account remains active and the information is needed for scheduling, customer management, reporting, support, security, or legal compliance. When an owner requests deletion of a shop account, live shop data may be removed from active paths and placed into a restricted deleted archive node for controlled retention, audit, dispute handling, fraud prevention, restoration review, or legal compliance. When a crew member deletes an account, the user account access is removed while limited historical business records may remain in anonymized or operational form to preserve appointment history and reporting integrity.',
        ),
        _LegalSection(
          title: '8. Security',
          body:
              'We use reasonable technical and organizational measures designed to protect account and business data, including authentication controls, database security rules, role-based access logic, and controlled backend operations. No system can guarantee absolute security, and users are responsible for protecting their devices, credentials, and internal access permissions.',
        ),
        _LegalSection(
          title: '9. Account Deletion',
          body:
              'If an owner deletes a Barbero account, the live shop environment may be removed from active use, including crew records, appointments, customers, schedules, and related operational content, subject to limited archived retention where required for security, audit, recovery review, or legal reasons. If a crew member deletes an account, only that individual account access is removed, while the shop may retain limited non-login historical records connected to past operations.',
        ),
        _LegalSection(
          title: '10. International Processing',
          body:
              'Because Barbero uses cloud infrastructure and remote technical services, information may be processed in jurisdictions other than the physical location of the shop or end user. Where this occurs, reasonable safeguards and provider commitments may be relied upon to support secure processing and service continuity.',
        ),
        _LegalSection(
          title: '11. Changes to this Policy',
          body:
              'We may update this Privacy Policy from time to time to reflect service improvements, operational changes, legal requirements, or security practices. The latest in-app version should be treated as the current operational policy text for the software deployment.',
        ),
        _LegalSection(
          title: '12. Contact',
          body:
              'Questions about Barbero privacy practices, business account data, or account deletion requests should be directed to the business or support contact responsible for the Barbero deployment and customer relationship.',
        ),
      ],
    );
  }
}

class BarberoTermsPage extends StatelessWidget {
  const BarberoTermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalPageScaffold(
      title: 'Terms & Conditions',
      sections: [
        _LegalSection(
          title: '1. Service Description',
          body:
              'Barbero is a software service provided to barber shops and similar businesses for appointment scheduling, team administration, service configuration, pricing management, customer management, reporting, and related operational workflows. The application is intended for business use by authorized owners and invited staff.',
        ),
        _LegalSection(
          title: '2. Business Accounts and Roles',
          body:
              'The person who registers a new shop account is treated as the owner account unless otherwise configured by the system. Owners may invite crew members such as senior barbers, barbers, or assistants and assign role-based permissions. Crew users must only access a shop through a valid invitation or authorized assignment. Creating false shops, fake identities, or unauthorized access paths is prohibited.',
        ),
        _LegalSection(
          title: '3. Account Responsibility',
          body:
              'Users are responsible for maintaining the confidentiality of their credentials, ensuring that devices are used securely, and restricting access to authorized people only. Shop owners are responsible for the internal management of permissions and for the lawful use of customer and staff data entered into the system.',
        ),
        _LegalSection(
          title: '4. Acceptable Use',
          body:
              'Users may not use the service to violate law, infringe privacy rights, impersonate others, disrupt the platform, reverse engineer protected service components where prohibited, upload unlawful content, or misuse appointment workflows for spam, harassment, fraud, or misleading commercial activity.',
        ),
        _LegalSection(
          title: '5. Operational Data',
          body:
              'Shops are responsible for the accuracy of the business information, schedules, prices, service durations, customer details, and crew details they maintain. Barbero may rely on the data provided by the shop to process bookings, reporting, availability, and notifications. Incorrect input may affect booking accuracy, historical data quality, and reporting output.',
        ),
        _LegalSection(
          title: '6. Availability and Changes',
          body:
              'We may modify, improve, suspend, or discontinue features, workflows, or infrastructure components from time to time in order to maintain the service, improve reliability, address abuse, comply with law, or evolve the product. We do not guarantee uninterrupted operation at every moment, although the service is intended to support routine day-to-day business use.',
        ),
        _LegalSection(
          title: '7. Fees and Commercial Relationship',
          body:
              'Where the software is sold, licensed, subscribed to, or otherwise provided commercially to a shop, the applicable commercial agreement, invoice, proposal, or subscription arrangement governs pricing, payment terms, implementation scope, and service package details. These in-app terms operate together with that commercial relationship.',
        ),
        _LegalSection(
          title: '8. Intellectual Property',
          body:
              'The Barbero software, interface, workflows, code, visual assets, service structure, and supporting materials remain the intellectual property of the software provider or its licensors, except for business content and customer information entered by the shop. No ownership of the software itself transfers to the shop unless expressly agreed in writing.',
        ),
        _LegalSection(
          title: '9. Termination and Deletion',
          body:
              'An owner may request account deletion from within the application. When that occurs, live shop data may be removed from active service and may be retained in a restricted deleted archive for security, dispute, legal, or restoration review purposes. Crew members may delete only their own Barbero access, while the shop may retain limited historical operational records. We may also suspend or terminate access in cases of misuse, security risk, non-payment, fraud, unlawful conduct, or material violation of these terms.',
        ),
        _LegalSection(
          title: '10. Limitation of Liability',
          body:
              'To the maximum extent permitted by applicable law, the software is provided on an as-available basis and the provider is not liable for indirect, incidental, special, consequential, exemplary, or lost-profit damages arising from use of the service, data entry errors, appointment issues, third-party outages, or unauthorized access caused by user-side credential or device compromise. Direct liability, if any, should be limited to the amount paid for the relevant service period unless a separate written agreement states otherwise.',
        ),
        _LegalSection(
          title: '11. Compliance and Legal Review',
          body:
              'Shops remain responsible for ensuring that their use of the platform, their notices to customers, their cancellation practices, their communications, and their internal data handling comply with the laws and regulations applicable to their business. Where a shop requires jurisdiction-specific documentation, legal review should be obtained before relying on the in-app text as a final legal document.',
        ),
        _LegalSection(
          title: '12. Updates to the Terms',
          body:
              'These Terms & Conditions may be updated from time to time to reflect operational, technical, commercial, or legal changes. Continued use of the software after an update constitutes acceptance of the updated terms, unless a separate written agreement provides otherwise.',
        ),
      ],
    );
  }
}
